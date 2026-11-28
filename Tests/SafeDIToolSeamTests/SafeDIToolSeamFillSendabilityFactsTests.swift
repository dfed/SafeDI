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

/// The per-type facts' column of whether each fill of a seam call builds in a `@Sendable` function
/// (`TypeFactsFill.buildsInSendableFunction`), against what the tree decides (`ScopeGenerator.buildsInSendableFunction(ofFill:)`):
/// `Top`, a seam of `Feature`, passes up the places `first` of `SubA` and `second` of `SubB`, which `Host`, a seam of
/// `Middle`, fills; `DefaultFirst`, `first`'s fill, builds `SubB` again, which passes the enclosing fill of `second` on.
struct SafeDIToolSeamFillSendabilityFactsTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try? FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func typeFacts_marksFillSendable_whenCallInsideAnotherFillReentersItThroughSendableInstantiator() async throws {
		// `DefaultFirst` builds `SubB` again in a `SendableInstantiator`'s `@Sendable` function, which does not enclose
		// `Top`'s call and refers to `second`: `second` builds in a `@Sendable` function, `first` does not, though the seam
		// takes neither `@Sendable`.
		let edges = try await fillEdges(defaultFirstDeclarations: ["@Instantiated let subBBuilder: SendableInstantiator<SubB>"], middleTypes: [])

		#expect(edges == [
			"Top as top: Top -> DefaultFirst as first: any First fill: column false, hole false, tree false",
			"Top as top: Top -> DefaultSecond as second: any Second fill: column true, hole false, tree true",
			"SubB as subBBuilder: SendableInstantiator<SubB> -> DefaultSecond as second: any Second fill: column true, hole false, tree true",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func typeFacts_marksFillSendable_whenCycleMakesFunctionOfReenteringCallSendable() async throws {
		// `Loop`'s builder function is plain where `DefaultFirst` builds it, but `Inner`, built in a `SendableInstantiator`,
		// closes a cycle on it, which makes it `@Sendable`: `Loop`'s call of `SubB` refers to `second` from it.
		let edges = try await fillEdges(
			defaultFirstDeclarations: ["@Instantiated let loopBuilder: Instantiator<Loop>"],
			middleTypes: [
				seamFixtureType(named: "Loop", declarations: ["@Instantiated let innerBuilder: SendableInstantiator<Inner>", "@Instantiated let subB: SubB"]),
				seamFixtureType(named: "Inner", declarations: ["@Instantiated let loopBuilder: Instantiator<Loop>"]),
			],
		)

		#expect(edges == [
			"Top as top: Top -> DefaultFirst as first: any First fill: column false, hole false, tree false",
			"Top as top: Top -> DefaultSecond as second: any Second fill: column true, hole false, tree true",
			"SubB as subB: SubB -> DefaultSecond as second: any Second fill: column true, hole false, tree true",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func typeFacts_foldsFillSendabilityInWorkLinearInCalls_whenFillsNestCallsOfSeamsDeep() async throws {
		// `Root` calls `Seam0`, whose place `Impl0` fills by calling `Seam1`, and so on, n calls deep: each call is a node
		// and a fill edge, and the keys of each call's fills are dropped where the call resolves them, so the fold does
		// work linear in the calls. A summary that kept every key beneath it, or a walk per path, would grow with n².
		var work = [Int]()
		for depth in [8, 32] {
			var core = [String]()
			var app = [String]()
			for index in 0..<depth {
				core.append("public protocol Place\(index) {}")
				core.append(seamFixtureType(named: "Seam\(index)", isSeam: true, declarations: ["@Instantiated let place\(index): any Place\(index)"]))
				let declarations = index + 1 < depth ? ["@Instantiated let seam\(index + 1): Seam\(index + 1)"] : []
				app.append(SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "Impl\(index)", fulfilling: "Place\(index)", declarations: declarations))
			}
			app.append(seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let seam0: Seam0"]))
			let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: core, app: app)
			let (stream, continuation) = AsyncStream.makeStream(of: GenerationWork.self)
			try await GenerationWork.$observer.withValue({ continuation.yield($0) }) {
				_ = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: depth == 8 ? .recordingIssues : .skipped, filesToDelete: &filesToDelete)
			}
			continuation.finish()
			var count = 0
			for await step in stream where step.step == .foldingFillSendability {
				count += step.elementCount
			}
			work.append(count)
		}
		// 13 visits per call: the two graphs that hold every call visit five per call, and three graphs per call that hold
		// one call visit one each.
		#expect(work == [104, 416])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// Each fill edge of `Host`'s per-type facts, in node and edge order: its source and target, the column, whether the
	/// seam takes the fill `@Sendable`, and what the tree decided at the places of its fill.
	private mutating func fillEdges(defaultFirstDeclarations: [String], middleTypes: [String]) async throws -> [String] {
		let modules = [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol First {}",
				"public protocol Second {}",
				seamFixtureType(named: "SubA", isSeam: true, declarations: ["@Instantiated let first: any First"]),
				seamFixtureType(named: "SubB", isSeam: true, declarations: ["@Instantiated let second: any Second"]),
				seamFixtureType(named: "Top", isSeam: true, declarations: ["@Instantiated let subA: SubA", "@Instantiated let subB: SubB"]),
			]),
			ModuleFixture(name: "Middle", packageName: "Mid", swiftFileContent: (middleTypes + [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultFirst", fulfilling: "First", declarations: defaultFirstDeclarations),
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultSecond", fulfilling: "Second", declarations: []),
				seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated let top: Top"]),
			]).map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let host: Host"])].map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
		]
		let (stream, continuation) = AsyncStream.makeStream(of: TypeFactsReport.self)
		_ = try await ConstructionMemoOracle.$observer.withValue({ _, _, report in continuation.yield(report) }) {
			try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
		continuation.finish()
		var reports = [TypeFactsReport]()
		for await report in stream where report.root == "Host" && !report.forMockGeneration {
			reports.append(report)
		}
		let report = try #require(reports.last)
		var treeByKey = [String: Set<Bool>]()
		for place in report.places {
			if let fillKey = place.fillKey, let buildsInSendableFunction = place.fillBuildsInSendableFunction {
				treeByKey[fillKey, default: []].insert(buildsInSendableFunction)
			}
		}
		var lines = [String]()
		for node in report.nodes {
			for (target, edge) in zip(node.edges, node.edgeFacts) where edge.isFill {
				let tree = (edge.fillKey.flatMap { treeByKey[$0] } ?? []).sorted { !$0 && $1 }.map(String.init).joined(separator: " and ")
				lines.append("\(node.description) -> \(report.nodes[target].description): column \(edge.fillBuildsInSendableFunction), hole \(edge.fillHoleIsSendable), tree \(tree)")
			}
		}
		return lines
	}
}
