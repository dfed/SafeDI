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

/// The graph's answer of whether an edge builds its child in its parent's body (`TypeFactsBuildsInCallersBody`), pinned
/// for one cell of each answer. Every test graph compares the answers it decides with the layout
/// (`TypeFactsBuildsInCallersBodyChecks`); these show the answer each cell gets.
struct SafeDIToolTypeFactsBuildsInCallersBodyTests: ~Copyable {
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
	mutating func generate_buildsConstantInCallersBody_whenConstantInstantiatesNothing() async throws {
		let observed = try await observe([
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let leaf: Leaf"]),
			seamFixtureType(named: "Leaf", isFinalClass: true, declarations: []),
		])

		#expect(answer(intoNodeDescribed: "Leaf as leaf: Leaf", in: observed.report) == "inCallersBody", "\(observed.report.world)")
		#expect(observed.places.map(\.hasFunction) == [false])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsConstantInOwnFunction_whenConstantInstantiatesChild() async throws {
		let observed = try await observe([
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let parent: Parent"]),
			seamFixtureType(named: "Parent", isFinalClass: true, declarations: ["@Instantiated let leaf: Leaf"]),
			seamFixtureType(named: "Leaf", isFinalClass: true, declarations: []),
		])

		#expect(answer(intoNodeDescribed: "Parent as parent: Parent", in: observed.report) == "inOwnFunction", "\(observed.report.world)")
		#expect(observed.places.first { $0.declaration == "Parent as parent: Parent" }?.hasFunction == true)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_owesWhetherConstantBuildsInCallersBody_whenConstantIsSeamCall() async throws {
		let observed = try await observe([
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let feature: Feature"]),
			seamFixtureType(named: "Feature", isSeam: true, declarations: ["@Instantiated let leaf: Leaf"]),
			seamFixtureType(named: "Leaf", declarations: []),
		])

		#expect(answer(intoNodeDescribed: "Feature as feature: Feature", in: observed.report) == "owed", "\(observed.report.world)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_answersEveryVariantOfCallerAlike_whenTwoVariantsCallSameLeaf() async throws {
		// `First` declares `x` by value and `Second` lazily, so `Child` has a variant per parent, each of which calls `Leaf`.
		let observed = try await observe([
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let first: First", "@Instantiated let second: Second"]),
			seamFixtureType(named: "First", isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let child: Child"]),
			seamFixtureType(named: "Second", isFinalClass: true, declarations: ["@Instantiated let x: LazilyInstantiated<X>", "@Instantiated let child: Child"]),
			seamFixtureType(named: "Child", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: X?", "@Instantiated let leaf: Leaf"]),
			seamFixtureType(named: "Leaf", isFinalClass: true, declarations: []),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
		])

		let child = try #require(observed.report.places.first { $0.declaration == "Child as child: Child" }?.node)
		#expect(observed.report.variantCountsByNode[child] == 2, "\(observed.report.world)")
		#expect(answer(intoNodeDescribed: "Leaf as leaf: Leaf", in: observed.report) == "inCallersBody", "\(observed.report.world)")
		#expect(observed.places.filter { $0.declaration == "Leaf as leaf: Leaf" }.map(\.hasFunction) == [false, false])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The report of `Root`'s production world and the places the oracle compared in it, from a run of `types`.
	private mutating func observe(_ types: [String]) async throws -> (report: TypeFactsReport, places: [TypeFactsBuildsInCallersBodyComparison.Place]) {
		let (reports, reportContinuation) = AsyncStream.makeStream(of: TypeFactsReport.self)
		let (comparisons, comparisonContinuation) = AsyncStream.makeStream(of: TypeFactsBuildsInCallersBodyComparison.self)
		_ = try await TypeFactsBuildsInCallersBodyObservation.$comparesLayout.withValue({ comparisonContinuation.yield($0) }) {
			try await ConstructionMemoOracle.$observer.withValue({ _, _, report in reportContinuation.yield(report) }) {
				try await executeSafeDIToolTest(swiftFileContent: types, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
			}
		}
		reportContinuation.finish()
		comparisonContinuation.finish()
		var rootReports = [TypeFactsReport]()
		for await report in reports where report.root == "Root" && !report.forMockGeneration {
			rootReports.append(report)
		}
		var places = [TypeFactsBuildsInCallersBodyComparison.Place]()
		for await comparison in comparisons where comparison.root == "Root" {
			places.append(contentsOf: comparison.places)
		}
		return (try #require(rootReports.last), places)
	}

	/// The answer for the first edge of `report`'s graph into the node described as `description`.
	private func answer(intoNodeDescribed description: String, in report: TypeFactsReport) -> String? {
		let graph = report.graph
		return (0..<graph.graph.edgeCount).first { graph.description(ofNode: Int(graph.edgeFacts[$0].child)) == description }.map { "\(graph.buildsInCallersBody.answers[$0])" }
	}
}
