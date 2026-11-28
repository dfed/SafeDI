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

/// The receives that leave a seam's world, with where each is declared (`TypeFactsWorld.receiversLeavingRoot()`), as a seam's
/// parameters call them their receivers. Every test of the suites also compares the column with the walk of the seam's tree
/// (`TypeFactsRootReceiversChecks`); these spell what the column holds for each shape.
struct SafeDIToolSeamTypeFactsReceiversTests: ~Copyable {
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
	mutating func receivers_holdDeclaringTypeLocationAndModule_whenSeamsTreeReceivesValue() async throws {
		let (report, output) = try await seamReport(ofSeam: "Panel", modules: [
			ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: User", "@Instantiated let panel: Panel"]),
				seamFixtureType(named: "Panel", isSeam: true, declarations: ["@Instantiated let gauge: Gauge"]),
				seamFixtureType(named: "Gauge", declarations: ["@Received let user: User"]),
				seamFixtureType(named: "User", declarations: []),
			]),
		])
		let app = try #require(output.modules["App"]).fixtures

		#expect(report.nodes.map(\.receiversLeavingRoot) == [
			[],
			["Gauge receives user: User at \(NormalizedFilePath(app.compilerPath(of: "Gauge.swift")).path):7:5 in App"],
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func receivers_spellFulfillingPropertyAsAliasSpellsIt_whenSeamsTreeReceivesValueThroughAlias() async throws {
		let (report, output) = try await seamReport(ofSeam: "Panel", modules: [
			ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, declarations: [#"@Instantiated(fulfilledByType: "DefaultUser") let user: UserProtocol"#, "@Instantiated let panel: Panel"]),
				seamFixtureType(named: "Panel", isSeam: true, declarations: ["@Instantiated let gauge: Gauge"]),
				seamFixtureType(named: "Gauge", declarations: [#"@Received(fulfilledByDependencyNamed: "user", ofType: UserProtocol.self) let account: any UserProtocol"#]),
				"public protocol UserProtocol {}",
				seamFixtureType(named: "DefaultUser", declarations: [], conformances: ", UserProtocol"),
			]),
		])
		let app = try #require(output.modules["App"]).fixtures

		#expect(report.nodes.map(\.receiversLeavingRoot) == [
			[],
			["Gauge receives user: any UserProtocol as alias account: any UserProtocol at \(NormalizedFilePath(app.compilerPath(of: "Gauge.swift")).path):7:5 in App"],
			[],
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func receivers_nameReceiversModule_whenReceiveIsDeclaredInAnotherModule() async throws {
		let (report, output) = try await seamReport(ofSeam: "Panel", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				seamFixtureType(named: "Gauge", declarations: ["@Received let user: User"]),
				seamFixtureType(named: "User", declarations: []),
			]),
			ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: [
				"import Feature\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: User", "@Instantiated let panel: Panel"]),
				"import Feature\n\n" + seamFixtureType(named: "Panel", isSeam: true, declarations: ["@Instantiated let gauge: Gauge"]),
			], dependencies: ["Feature"]),
		])
		let feature = try #require(output.modules["Feature"]).fixtures

		#expect(report.nodes.map(\.receiversLeavingRoot) == [
			[],
			["Gauge receives user: User at \(NormalizedFilePath(feature.compilerPath(of: "Gauge.swift")).path):7:5 in Feature"],
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func receivers_nameReceivesInsideNestedSeamAtCall_whenSeamCallsSeamOfAnotherModule() async throws {
		let (report, output) = try await seamReport(ofSeam: "Panel", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let gauge: Gauge"]),
				seamFixtureType(named: "Gauge", declarations: ["@Received let user: User"]),
				seamFixtureType(named: "User", declarations: []),
			]),
			ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: [
				"import Feature\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: User", "@Instantiated let panel: Panel"]),
				"import Feature\n\n" + seamFixtureType(named: "Panel", isSeam: true, declarations: ["@Instantiated let inner: Inner"]),
			], dependencies: ["Feature"]),
		])
		let feature = try #require(output.modules["Feature"]).fixtures

		#expect(report.nodes.map(\.receiversLeavingRoot) == [
			[],
			["Gauge receives user: User at \(NormalizedFilePath(feature.compilerPath(of: "Gauge.swift")).path):7:5 in Feature"],
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func receivers_followDeclarationOrder_whenTwoTypesReceiveOneLabel() async throws {
		let (report, output) = try await seamReport(ofSeam: "Panel", modules: [
			ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: User", "@Instantiated let panel: Panel"]),
				seamFixtureType(named: "Panel", isSeam: true, declarations: ["@Instantiated let zebra: Zebra", "@Instantiated let ant: Ant"]),
				seamFixtureType(named: "Zebra", declarations: ["@Received let user: User"]),
				seamFixtureType(named: "Ant", declarations: ["@Received let user: User"]),
				seamFixtureType(named: "User", declarations: []),
			]),
		])
		let app = try #require(output.modules["App"]).fixtures

		#expect(report.nodes.map(\.receiversLeavingRoot) == [
			[],
			["Zebra receives user: User at \(NormalizedFilePath(app.compilerPath(of: "Zebra.swift")).path):7:5 in App"],
			["Ant receives user: User at \(NormalizedFilePath(app.compilerPath(of: "Ant.swift")).path):7:5 in App"],
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The type facts report of the last tree built for `seam`'s own production world, and the run's output.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func seamReport(ofSeam seam: String, modules: [ModuleFixture]) async throws -> (report: TypeFactsReport, output: MultiModuleTestOutput) {
		let (stream, continuation) = AsyncStream.makeStream(of: TypeFactsReport.self)
		var filesToDelete = [URL]()
		let output = try await ConstructionMemoOracle.$observer.withValue({ _, _, report in continuation.yield(report) }) {
			try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .swiftPackagePlugin, filesToDelete: &filesToDelete)
		}
		self.filesToDelete.append(contentsOf: filesToDelete)
		continuation.finish()
		var reports = [TypeFactsReport]()
		for await report in stream where report.root == seam && !report.forMockGeneration {
			reports.append(report)
		}
		return (try #require(reports.last), output)
	}
}
