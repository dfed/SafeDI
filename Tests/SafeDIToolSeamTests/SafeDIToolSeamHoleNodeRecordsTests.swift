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

/// A hole's place made from a seam's world (`NodeRecords+SeamHole.swift`), with no tree of places: every test compares it with
/// the tree's place (`NodeRecordsChecks`); these show which seam trees node records make, and which they refuse.
struct SafeDIToolSeamHoleNodeRecordsTests: ~Copyable {
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
	mutating func generate_makesHolesPlacesAsTheSeamsTreeWritesThem_whenEachHoleIsReachedAlongOnePath() async throws {
		let reports = try await reportsOfOffice(officeDeclarations: ["@Instantiated let panel: Panel", "@Instantiated let panelBuilder: Instantiator<Other>"])
		#expect(reports.map(\.refusal) == [nil])
		#expect(reports.map(\.differences) == [[]])
		// `panel`, `panelBuilder`, the hole beneath each, and the payload the tree binds before each, a place of its own.
		#expect(reports.map(\.treePlaceCount) == [6])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_refusesSeamsWorld_whenItReachesAHoleAlongTwoPaths() async throws {
		// `Panel`'s node is built beneath `first` and `second`, and its hole's site reads the level each route binds.
		let reports = try await reportsOfOffice(officeDeclarations: ["@Instantiated let first: First", "@Instantiated let second: Second"])
		#expect(reports.map(\.refusal) == ["holeOnSeveralPaths"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_refusesSeamsWorld_whenAHoleIsDeclaredBesideASiblingOnACycle() async throws {
		// `api` is declared before `childBuilder`, whose node is on the cycle through `Grand`, so the hole is classified first.
		let reports = try await reportsOfOffice(officeDeclarations: ["@Instantiated let looping: Looping"])
		#expect(reports.map(\.refusal) == ["cycle"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_refusesSeamsWorld_whenItReachesAHoleThroughALazyWrapper() async throws {
		// `panel`'s builder function binds what its hole's site reads apart.
		let reports = try await reportsOfOffice(officeDeclarations: ["@Instantiated let panel: LazilyInstantiated<Panel>"])
		#expect(reports.map(\.refusal) == ["holeInWrapper"])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The node records reports of `Office`, a seam whose module cannot fill `Api`, which declares `officeDeclarations`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func reportsOfOffice(officeDeclarations: [String]) async throws -> [NodeRecordsReport] {
		let modules = SafeDIToolSeamBuilderParameterTests.modules(
			feature: [
				"public protocol Api {}",
				seamFixtureType(named: "Panel", declarations: ["@Instantiated let api: any Api"]),
				seamFixtureType(named: "Other", declarations: ["@Instantiated let api: any Api"]),
				seamFixtureType(named: "First", declarations: ["@Instantiated let panel: Panel"]),
				seamFixtureType(named: "Second", declarations: ["@Instantiated let panel: Panel"]),
				seamFixtureType(named: "Looping", declarations: ["@Instantiated let api: any Api", "@Instantiated let childBuilder: Instantiator<Child>"]),
				seamFixtureType(named: "Child", declarations: ["@Instantiated let grandBuilder: Instantiator<Grand>"]),
				seamFixtureType(named: "Grand", declarations: ["@Instantiated let childBuilder: Instantiator<Child>"]),
				seamFixtureType(named: "Office", isSeam: true, declarations: officeDeclarations),
			],
			app: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultApi", fulfilling: "Api", declarations: []),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let office: Office"]),
			],
		)
		let (stream, continuation) = AsyncStream.makeStream(of: NodeRecordsReport.self)
		_ = try await NodeRecordsObservation.$observer.withValue({ continuation.yield($0) }) {
			try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
		continuation.finish()
		var reports = [NodeRecordsReport]()
		for await report in stream where report.root == "Office" {
			reports.append(report)
		}
		return reports
	}
}
