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

/// A seam's hole leaf in its world's variant key. A hole's site passes its fill only labels its owner binds, so the
/// owner's own reads key the site, and the route payloads that reach the owner are written on the parents' nodes, which
/// their own reads key. Where the places of one hole see the fill's labels in forms the fill could not read alike,
/// validation rejects the graph, so a hole leaf reads nothing. These graphs are the accepted shapes in which the places
/// of one hole differ above the owner; each must keep the owner one variant, and fails if a hole's site comes to read
/// above its owner.
struct SafeDIToolSeamHoleVariantKeyTests: ~Copyable {
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

	@Test(arguments: [
		// (the fill’s declarations, First’s declarations, Second’s declarations)
		// The fill reads `y` only if available, and only `First` declares it.
		(["@Received(onlyIfAvailable: true) let y: Y?"], ["@Instantiated let y: Y"], [String]()),
		// The fill reads nothing, and `First` and `Second` declare `y` in different forms.
		([String](), ["@Instantiated let y: Y"], ["@Instantiated let y: LazilyInstantiated<Y>"]),
		// The fill reads `y`, and only `Second` declares a lazy `z` beside it.
		(["@Received let y: Y"], ["@Instantiated let y: Y"], ["@Instantiated let y: Y", "@Instantiated let z: LazilyInstantiated<Y>"]),
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keysTheHolesOwnerAsOneVariant_whenThePlacesDifferOnlyAboveTheOwner(
		fillDeclarations: [String],
		firstDeclarations: [String],
		secondDeclarations: [String],
	) async throws {
		let report = try await officeReport(
			fillDeclarations: fillDeclarations,
			firstDeclarations: firstDeclarations,
			secondDeclarations: secondDeclarations,
		)

		#expect(report.places.count(where: { $0.declaration == "Panel as panel: Panel" }) == 2, "\(report.world)")
		#expect(variantCount(ofNodeDeclaring: "Panel as panel: Panel", in: report) == 1, "\(report.world)")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The world report of `Office`, a seam of `Feature` that builds `Panel` beneath `First` and `Second`; `Panel`’s hole
	/// `api` is filled in `App` by `DefaultApi`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func officeReport(
		fillDeclarations: [String],
		firstDeclarations: [String],
		secondDeclarations: [String],
	) async throws -> TypeFactsReport {
		let modules = SafeDIToolSeamBuilderParameterTests.modules(
			feature: [
				"public protocol Api {}",
				seamFixtureType(named: "Y", declarations: []),
				seamFixtureType(named: "Panel", declarations: ["@Instantiated let api: any Api"]),
				seamFixtureType(named: "First", declarations: firstDeclarations + ["@Instantiated let panel: Panel"]),
				seamFixtureType(named: "Second", declarations: secondDeclarations + ["@Instantiated let panel: Panel"]),
				seamFixtureType(named: "Office", isSeam: true, declarations: ["@Instantiated let first: First", "@Instantiated let second: Second"]),
			],
			app: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultApi", fulfilling: "Api", declarations: fillDeclarations),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let office: Office"]),
			],
		)
		let (stream, continuation) = AsyncStream.makeStream(of: TypeFactsReport.self)
		_ = try await ConstructionMemoOracle.$observer.withValue(TaskLocalFunction { _, _, report in continuation.yield(report) }) {
			try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
		continuation.finish()
		var reports = [TypeFactsReport]()
		for await report in stream where report.root == "Office" && !report.forMockGeneration {
			reports.append(report)
		}
		return try #require(reports.last, "no world report of Office")
	}

	private func variantCount(ofNodeDeclaring declaration: String, in report: TypeFactsReport) -> Int? {
		guard let node = report.places.first(where: { $0.declaration == declaration })?.node else {
			return nil
		}
		return report.variantCountsByNode[node]
	}
}
