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

/// A seam's levels declare no initializer that takes only a builder. The two callers that build a seam's levels from one
/// builder – the seam's plain initializer, which a person calls with a builder that takes no scope, and a caller that
/// fills an optional place nothing fulfills with `{ nil }` – each declare one local function per level they reach,
/// which builds the level from its members, and a looping level's function calls itself. Each cell here builds a level
/// that loops, a level of another module's seam, a level of the `@Sendable` family and a place held in a wrapper that
/// forwards nothing beneath a builder that takes nothing, and compares the values with the same graph built inline.
struct SafeDIToolSeamLevelsWithoutScopeTests: ~Copyable {
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
	mutating func generate_buildsEachLevelInALocalFunction_whenPlainInitializerTakesBuilders() async throws {
		let modules = Self.modules
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
			"Feature.swift": "",
		])
		try await expectValuesAndRetentionEqualInlineBuild(output, modules: modules, probes: [
			DifferentialValueProbe(name: "Home", expression: Self.plainInitializerCall, knownRightExpression: "Root().home"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsEachLevelInALocalFunction_whenCallerFillsOptionalPlaceNothingFulfillsWithNil() async throws {
		let modules = Self.modules
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": "",
		])
		try await expectValuesAndRetentionEqualInlineBuild(output, modules: modules, probes: [DifferentialValueProbe("Root()")])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The call of `Home`'s plain initializer that builds what `Root` builds inline.
	private static let plainInitializerCall = "Home(apiBuilder: { DefaultApi() }, gadgetSendableBuilder: { DefaultGadget() }, trackerOptionalBuilder: { nil }, trackerOptionalSendableBuilder: { nil }, widgetBuilder: { DefaultWidget() })"

	/// `Core` declares `Inner`, a seam with a place of `Api` and an optional place of `Tracker`, which `Home` passes up.
	/// `Feature`, whose seams people call, declares `Home`, a seam that holds the loop of `ScreenA` and `ScreenB`, each
	/// forwarding an `id` and holding a place of `Api`, the place `widgetBuilder` held in a wrapper that forwards nothing,
	/// the `Sendable` `Worker`, whose places are of the `@Sendable` family, and `Inner`. `App` fills every place but
	/// those of `Tracker`.
	private static let modules = [
		ModuleFixture(name: "Core", packageName: "Shop", swiftFileContent: [
			"public protocol Api {}",
			"public protocol Tracker: Sendable {}",
			"public protocol Gadget: Sendable {}",
			seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let api: any Api", "@Instantiated(onlyIfAvailable: true) let tracker: (any Tracker)?"]),
		]),
		ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
			"public protocol Widget {}",
			seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: [
				"@Instantiated let screenABuilder: Instantiator<ScreenA>",
				"@Instantiated let screenBBuilder: Instantiator<ScreenB>",
				"@Instantiated let widgetBuilder: ErasedInstantiator<(), any Widget>",
				"@Instantiated let workerBuilder: SendableInstantiator<Worker>",
				"@Instantiated let inner: Inner",
			]),
			seamFixtureType(named: "ScreenA", isFinalClass: true, declarations: ["@Forwarded let id: Int", "@Instantiated let api: any Api", "@Instantiated(onlyIfAvailable: true) let tracker: (any Tracker)?", "@Received let screenBBuilder: Instantiator<ScreenB>"]),
			seamFixtureType(named: "ScreenB", isFinalClass: true, declarations: ["@Forwarded let id: Int", "@Instantiated let api: any Api", "@Received let screenABuilder: Instantiator<ScreenA>"]),
			seamFixtureType(named: "Worker", declarations: ["@Instantiated let gadget: any Gadget", "@Instantiated(onlyIfAvailable: true) let tracker: (any Tracker)?"], conformances: ", Sendable"),
		].map { "import Core\n\n" + $0 }, swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration, dependencies: ["Core"]),
		ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
			seamFixtureType(named: "DefaultApi", isFinalClass: true, declarations: [], conformances: ", Api").replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Api.self])\n"),
			seamFixtureType(named: "DefaultWidget", isFinalClass: true, declarations: [], conformances: ", Widget").replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Widget.self])\n"),
			seamFixtureType(named: "DefaultGadget", declarations: [], conformances: ", Gadget").replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Gadget.self])\n"),
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let home: Home"]),
		].map { "import Core\nimport Feature\n\n" + $0 }, dependencies: ["Core", "Feature"]),
	]

	/// Expects `output`, the run of `modules`, to build the values the same graph built inline builds for each of
	/// `probes`, and to keep alive no more of them than the inline build keeps once each is released, calling each
	/// screen's instantiator with the `id` 7.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectValuesAndRetentionEqualInlineBuild(
		_ output: MultiModuleTestOutput,
		modules: [ModuleFixture],
		probes: [DifferentialValueProbe],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		guard compileVerificationIsEnabled else { return }
		let inlineModules = modules.map { module in
			ModuleFixture(
				name: module.name,
				packageName: module.packageName,
				swiftFileContent: inlineFixture(module.swiftFileContent),
				dependencies: module.dependencies,
			)
		}
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		let graph = try DifferentialValueGraph(
			name: "levels without scope",
			feature: DifferentialValuePath(output: output, modules: modules),
			knownRight: DifferentialValuePath(output: inlineOutput, modules: inlineModules),
			probes: probes,
			samples: ["ScreenA", "ScreenB"].map { DifferentialValueSample(type: "\($0).ForwardedProperties", expression: "7") },
			judgesRetention: true,
		)
		let comparison = try #require(try await DifferentialValueOracle.compare(graphs: [graph], filesToDelete: &filesToDelete)?.first?.result.get(), sourceLocation: sourceLocation)
		#expect(comparison.differences == [], sourceLocation: sourceLocation)
		#expect(comparison.retentionDifferences == [], sourceLocation: sourceLocation)
		#expect(comparison.retentionJudgedProbes == probes.map(\.name), sourceLocation: sourceLocation)
	}

	/// Expects `generatedFiles` to equal `expected`, recording the files generated when they do not, so a failure shows
	/// the output in full.
	private func expectGeneratedFiles(_ generatedFiles: [String: String]?, _ expected: [String: String], sourceLocation: SourceLocation = #_sourceLocation) {
		#expect(generatedFiles == expected, sourceLocation: sourceLocation)
		if let generatedFiles, generatedFiles != expected {
			Issue.record(Comment(rawValue: generatedFiles.sorted { $0.key < $1.key }.map { "=== \($0.key)\n\($0.value)" }.joined(separator: "\n")), sourceLocation: sourceLocation)
		}
	}
}
