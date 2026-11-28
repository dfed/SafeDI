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

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func receivers_nameOmittingCallAndItsTier_whenNestedSeamsTierOmitsReceive() async throws {
		// A `.safedi` carries the signature without positions, so `Shell`'s run reads no location for `Service`'s receive.
		let (shellReport, _) = try await seamReport(ofSeam: "Shell", modules: Self.tierOmissionModules, integration: .moduleInfo)

		#expect(shellReport.nodes.map(\.receiversLeavingRoot) == [
			[],
			["Badge receives theme: Theme? in Base through the call of Service at tier public, which passes nil for it: the tier omits it"],
		])
		#expect(shellReport.nodes.map(\.seamCall) == [nil, "calls Service at tier public"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func receivers_nameOmittingCallAndNoTier_whenNestedSeamTakesReceiveOnNoTier() async throws {
		let (outerReport, _) = try await seamReport(ofSeam: "Outer", modules: Self.tierOmissionModules, integration: .moduleInfo)

		#expect(outerReport.nodes.map(\.receiversLeavingRoot) == [
			[],
			["Badge receives theme: Theme? in Base through the call of Shell at tier public, which passes nil for it: no tier takes it"],
		])
		#expect(outerReport.nodes.map(\.seamCall) == [nil, "calls Shell at tier public"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func receivers_markReceiveFromReportedCall_whenSeamCallsSeamItsModuleReachesNoTierOf() async throws {
		let (stream, continuation) = AsyncStream.makeStream(of: TypeFactsReport.self)
		var paths = [String: FixturePaths]()
		await ConstructionMemoOracle.$observer.withValue({ _, _, report in continuation.yield(report) }) {
			await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
				paths = fixtures
				return """
				\(NormalizedFilePath(fixtures["Feature"]!.compilerPath(of: "Service.swift")).path):2:1: error: `Service` is `package`, so module `App`, in another package, cannot construct it in the code SafeDI generates. Make `Service` `public` to fix.
				\(NormalizedFilePath(fixtures["Feature"]!.compilerPath(of: "Service.swift")).path):2:1-2:8: fixit: public
				"""
			}) {
				try await executeSafeDIToolMultiModuleTest(modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
						seamFixtureType(named: "Badge", declarations: ["@Received(onlyIfAvailable: true) let theme: Theme?"]) + "\n\npublic struct Theme: Sendable {\n    public init() {}\n}",
						"@Instantiable(generateDependencyTree: true)\npackage final class Service: Instantiable {\n    public init(badge: Badge) {\n        self.badge = badge\n    }\n\n    @Instantiated public let badge: Badge\n}",
					]),
					ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
						"import Feature\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let panel: Panel"]),
						"import Feature\n\n" + seamFixtureType(named: "Panel", isSeam: true, declarations: ["@Instantiated let service: Service"]),
					], dependencies: ["Feature"]),
				], integration: .moduleInfo, filesToDelete: &filesToDelete)
			}
		}
		continuation.finish()
		var reports = [TypeFactsReport]()
		for await report in stream where report.root == "Panel" && !report.forMockGeneration {
			reports.append(report)
		}
		let report = try #require(reports.last)
		let feature = try #require(paths["Feature"])

		#expect(report.nodes.map(\.receiversLeavingRoot) == [
			[],
			["Badge receives theme: Theme? at \(NormalizedFilePath(feature.compilerPath(of: "Badge.swift")).path):7:5 in Feature, through a call the check of every construction reports"],
		])
		#expect(report.nodes.map(\.seamCall) == [nil, "calls Service at tier package, reported"])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Service`, whose `public` tier omits `theme`, which its `Badge` receives and whose type is `package`; `Shell`, in
	/// another package, which calls that tier, so no tier of `Shell` takes `theme`; and `Outer`, which calls `Shell`.
	private static let tierOmissionModules = [
		ModuleFixture(name: "Base", packageName: "Shop", swiftFileContent: [
			"@Instantiable\npublic struct Badge: Instantiable {\n    package init(theme: Theme?) {\n        self.theme = theme\n    }\n\n    @Received(onlyIfAvailable: true) let theme: Theme?\n}\n\npackage struct Theme {}",
			seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
		]),
		ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: ["import Base\n\n" + seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let service: Service"])], dependencies: ["Base"]),
		ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
			"import Mid\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let outer: Outer"]),
			"import Mid\n\n" + seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated let shell: Shell"]),
		], dependencies: ["Base", "Mid"]),
	]

	/// The type facts report of the last tree built for `seam`'s own production world, and the run's output.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func seamReport(ofSeam seam: String, modules: [ModuleFixture], integration: MultiModuleIntegration = .swiftPackagePlugin) async throws -> (report: TypeFactsReport, output: MultiModuleTestOutput) {
		let (stream, continuation) = AsyncStream.makeStream(of: TypeFactsReport.self)
		var filesToDelete = [URL]()
		let output = try await ConstructionMemoOracle.$observer.withValue({ _, _, report in continuation.yield(report) }) {
			try await executeSafeDIToolMultiModuleTest(modules: modules, integration: integration, filesToDelete: &filesToDelete)
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
