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
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// The per-type facts of a fill (`TypeFactsGraph`'s fill channel): the edge to a fill binds the fields of the place it
/// fills, in their declared order, so what the fill's tree reads of them stops at the call, and the fill binds its hole's
/// property as being built for its tree beneath it, as the tree's fill does (`fillUnderConstruction`), while the fill's own
/// read of that label is the caller's. A fill the channel does not model yet is refused by name and counted, and keeps the
/// fact owed (`TypeFactsOwedFacts.fillBeingBuilt`).
struct SafeDIToolSeamFillChannelFactsTests: ~Copyable {
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
	mutating func generate_answersPlaceOfOneSeamApart_whenItIsCalledInsideFillOfPlaceWithItsPlacesLabelAndBesideIt() async throws {
		// `Root` calls `Home`, filling its `service` with `LiveService`, which calls `Inner`, and calls `Inner` itself too.
		// `Inner`'s place is also `service`: the fill of it reads that label of its caller, which inside the fill of
		// `Home`'s `service` is still being built and beside it is none. The two places of `inner` are two variants, and no
		// answer is owed.
		let report = try await rootReport(of: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Service {}",
				"public protocol Tracker {}",
				seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated public let service: any Tracker"]),
				seamFixtureType(named: "Home", isSeam: true, declarations: ["@Instantiated public let service: any Service"]),
			]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveService", fulfilling: "Service", declarations: ["@Instantiated public let inner: Inner"]),
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveTracker", fulfilling: "Tracker", declarations: []),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let home: Home", "@Instantiated public let inner: Inner"]),
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		])

		let findings = TypeFactsChecks.findings(of: report)
		#expect(findings.findingsByCheck[10] == nil, "\(findings.findingsByCheck[10] ?? [])")
		#expect(findings.check10OwedByFact.isEmpty)
		let inner = try #require(report.nodes.firstIndex { $0.description == "Inner as inner: Inner" })
		#expect(report.places.count { $0.node == inner } == 2)
		#expect(report.variantCountsByNode[inner] == 2, "\(report.world)")
		for node in report.nodes where node.description.hasSuffix(" fill") {
			#expect(!node.owedFacts.contains("fillBeingBuilt"), "\(node.description)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_stopsFillsReadsOfFieldsAtTheCall_whenFillReceivesValueTheSeamsTreeDeclaresBeforeThePlace() async throws {
		// `LiveService` receives `session`, which `Home` declares before both places: each fill binds it as a field, so
		// neither the call nor `Root` reads it from above, and each fill's own read of its place's label is the caller's.
		let report = try await rootReport(of: Self.twoPlacesFilledByOneType)

		let call = try #require(report.nodes.first { $0.description == "Home as home: Home" })
		#expect(!call.readsFromAbove.contains { $0.hasSuffix("(session)") }, "\(call.readsFromAbove)")
		#expect(call.readsFromAbove.contains("value(service)"), "\(call.readsFromAbove)")
		#expect(call.readsFromAbove.contains("value(backup)"), "\(call.readsFromAbove)")
		#expect(report.fillRefusals == [nil, nil], "\(report.fillRefusals)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_refusesFillAsCloserAndKeepsItsTreeOwed_whenFillsTreeBuildsPropertyOfSeamsPath() async throws {
		// `DefaultGadget`, which fills `Mid`'s `gadget` in `Root`'s tree, builds `midMaker` again: it closes a cycle on the path
		// of the seam it fills, which the channel does not model yet.
		let report = try await lastReport(
			of: SafeDIToolSeamBuilderParameterTests.fillCycleModules(
				feature: [
					seamFixtureType(named: "Panel", declarations: ["@Instantiated let widget: any Widget"]),
					seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let panelMaker: Instantiator<Panel>"]),
					SafeDIToolSeamBuilderParameterTests.shellOfInner,
				],
				upper: [
					SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Instantiated let midMaker: Instantiator<Mid>"]),
					seamFixtureType(named: "Mid", declarations: ["@Instantiated let gadget: any Gadget"]),
					SafeDIToolSeamBuilderParameterTests.hostOfShell,
				],
				app: [SafeDIToolSeamBuilderParameterTests.gadget(declarations: ["@Instantiated let midMaker: Instantiator<Mid>"]), SafeDIToolSeamBuilderParameterTests.rootOfHost],
			),
			root: "Root",
			expectingError: true,
		)

		#expect(report.fillRefusals == ["closer"], "\(report.fillRefusals)")
		Self.expectFillsOwe(in: report)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_refusesFillAsCycleReentryAndKeepsItsTreeOwed_whenSeamBuiltAgainReceivesLabelBoundOnEveryRouteToIt() async throws {
		// `Root` fills `Host`'s `gadget`, a place `Host`'s cycle re-enters: what the fill reads there the cycle hands it.
		let fixture = SafeDIToolSeamReenteredFillTests.Fixture(
			xIsFinalClass: true,
			featureTypes: [seamFixtureType(named: "Relay", isSeam: true, declarations: ["@Instantiated let x: X", "@Instantiated let subB: SubB"])],
			subBDeclarations: ["@Received let x: X", "@Instantiated let second: any Second"],
			defaultFirstDeclarations: ["@Instantiated let relay: Relay"],
			hostDeclarations: ["@Instantiated let x: X", "@Instantiated let top: Top"],
			gadgetDeclarations: ["@Received let x: X"],
		)
		let report = try await lastReport(of: fixture.modules, root: "Root")

		#expect(report.fillRefusals == ["cycleReentry"], "\(report.fillRefusals)")
		Self.expectFillsOwe(in: report)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_refusesFillOfMockWorld_whenCallingMockFillsPlaceOfCalledPublicMock() async throws {
		// `Screen`'s mock fills `S0`'s place: a mock root's world, whose fills the channel does not model yet.
		let report = try await lastReport(
			of: SafeDIToolSeamNestedUnfilledHoleTests.modules(depth: 2, app: [SafeDIToolSeamNestedUnfilledHoleTests.screen], publicMocks: true),
			root: "Screen",
			forMockGeneration: true,
		)

		#expect(report.fillRefusals == ["mockWorld"], "\(report.fillRefusals)")
		Self.expectFillsOwe(in: report)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Home`, a seam of `Feature`, declares `session` and then two places, `service` and `backup`, which `Root` in `App`
	/// fills with `LiveService`, whose `inner` receives `service` only if available.
	private static let twoPlacesFilledByOneType = [
		ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
			"public protocol Service {}",
			seamFixtureType(named: "Session", declarations: []),
			seamFixtureType(named: "Home", isSeam: true, declarations: ["@Instantiated public let session: Session", "@Instantiated public let service: any Service", "@Instantiated public let backup: any Service"]),
		]),
		ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveService", fulfilling: "Service", declarations: ["@Received public let session: Session", "@Instantiated public let inner: Inner"]),
			seamFixtureType(named: "Inner", declarations: ["@Received(onlyIfAvailable: true) public let service: (any Service)?"]),
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let home: Home"]),
		].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
	]

	/// The last production report of `Root`, the root of `App`, as `modules` are generated.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func rootReport(of modules: [ModuleFixture]) async throws -> TypeFactsReport {
		try await lastReport(of: modules, root: "Root")
	}

	/// The last report of `root`'s world, of its mock root's where `forMockGeneration`, as `modules` are generated, which
	/// throws where `expectingError`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func lastReport(of modules: [ModuleFixture], root: String, forMockGeneration: Bool = false, expectingError: Bool = false) async throws -> TypeFactsReport {
		let (stream, continuation) = AsyncStream.makeStream(of: TypeFactsReport.self)
		var thrownError: (any Error)?
		do {
			_ = try await ConstructionMemoOracle.$observer.withValue({ _, _, report in continuation.yield(report) }) {
				try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
			}
		} catch {
			thrownError = error
		}
		#expect((thrownError != nil) == expectingError, "\(String(describing: thrownError))")
		continuation.finish()
		var reports = [TypeFactsReport]()
		for await report in stream where report.root == root && report.forMockGeneration == forMockGeneration {
			reports.append(report)
		}
		return try #require(reports.last)
	}

	/// Expects every fill node of `report`'s world to owe the fill channel's fact, as the channel refuses each.
	private static func expectFillsOwe(in report: TypeFactsReport) {
		let fills = report.nodes.filter { $0.description.hasSuffix(" fill") }
		#expect(!fills.isEmpty)
		for node in fills {
			#expect(node.owedFacts.contains("fillBeingBuilt"), "\(node.description)")
		}
	}
}
