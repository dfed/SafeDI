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

/// Rule 3 of the seam contract on carriers: a builder the seam's carriers hand a place keeps alive only what that
/// place's fill reads, as the inline build's builder does. Each cell builds a graph across two modules with a seam and
/// again with every type built inline, and the comparator holds each SafeDI wrapper the root's value holds, with what
/// one call of it builds, releases the root, and counts the instances each build keeps alive.
struct SafeDIToolSeamCarrierRetentionTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test(arguments: PlaceWrapper.allCases, PlacePosition.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func retention_placeWrapperKeepsOnlyItsFillsReads_whenSiblingPlaceReadsAnotherValue(wrapper: PlaceWrapper, position: PlacePosition) async throws {
		let modules = CarrierCells.modules(
			seam: Self.siblingSeam(wrapper: wrapper, position: position),
			app: [Self.apiImpl(reading: "first: First"), Self.loggerImpl(reading: "second: Second"), CarrierCellRoot.structRoot.declaration(building: "home: Home")],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		try await CarrierCells.expectValuesAndRetentionEqualInlineBuild(output, modules: modules, samples: Self.screenSamples, filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func retention_siblingPlacesKeepOnlyTheirOwnReads_whenSiblingsReadUnequalSets() async throws {
		let modules = CarrierCells.modules(
			seam: [
				"public protocol Api {}",
				"public protocol Logger {}",
				seamFixtureType(named: "First", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Second", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Third", isFinalClass: true, declarations: []),
				seamFixtureType(named: "ScreenA", isFinalClass: true, declarations: ["@Instantiated let api: any Api"]),
				seamFixtureType(named: "ScreenB", isFinalClass: true, declarations: ["@Instantiated let logger: any Logger"]),
				seamFixtureType(named: "Screen", isFinalClass: true, declarations: [
					"@Forwarded let id: Int",
					"@Instantiated let first: First",
					"@Instantiated let second: Second",
					"@Instantiated let third: Third",
					"@Instantiated let screenABuilder: Instantiator<ScreenA>",
					"@Instantiated let screenBBuilder: Instantiator<ScreenB>",
				]),
				seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let screenBuilder: Instantiator<Screen>"]),
			],
			app: [Self.apiImpl(reading: "first: First", "second: Second"), Self.loggerImpl(reading: "second: Second", "third: Third"), CarrierCellRoot.structRoot.declaration(building: "home: Home")],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		try await CarrierCells.expectValuesAndRetentionEqualInlineBuild(output, modules: modules, samples: Self.screenSamples, filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func retention_childBuilderKeepsOnlyItsSubset_whenChildReadsStrictSubsetOfParentsValues() async throws {
		let modules = CarrierCells.modules(
			seam: [
				"public protocol Api {}",
				"public protocol Logger {}",
				seamFixtureType(named: "First", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Second", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Detail", isFinalClass: true, declarations: ["@Instantiated let api: any Api"]),
				seamFixtureType(named: "Screen", isFinalClass: true, declarations: [
					"@Forwarded let id: Int",
					"@Instantiated let first: First",
					"@Instantiated let second: Second",
					"@Instantiated let logger: any Logger",
					"@Instantiated let detailBuilder: Instantiator<Detail>",
				]),
				seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let screenBuilder: Instantiator<Screen>"]),
			],
			app: [Self.apiImpl(reading: "first: First"), Self.loggerImpl(reading: "first: First", "second: Second"), CarrierCellRoot.structRoot.declaration(building: "home: Home")],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		try await CarrierCells.expectValuesAndRetentionEqualInlineBuild(output, modules: modules, samples: Self.screenSamples, filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func retention_noRetainCycle_whenLoopScreensReadSeamValue() async throws {
		let modules = CarrierCells.modules(
			seam: [
				"public protocol Api {}",
				seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
				seamFixtureType(named: "ScreenA", isFinalClass: true, declarations: ["@Forwarded let id: Int", "@Instantiated let api: any Api", "@Received let screenBBuilder: Instantiator<ScreenB>"]),
				seamFixtureType(named: "ScreenB", isFinalClass: true, declarations: ["@Forwarded let id: Int", "@Instantiated let api: any Api", "@Received let screenABuilder: Instantiator<ScreenA>"]),
				seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: [
					"@Instantiated let session: Session",
					"@Instantiated let screenABuilder: Instantiator<ScreenA>",
					"@Instantiated let screenBBuilder: Instantiator<ScreenB>",
				]),
			],
			app: [Self.apiImpl(reading: "id: Int", "session: Session"), CarrierCellRoot.structRoot.declaration(building: "home: Home")],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		try await CarrierCells.expectValuesAndRetentionEqualInlineBuild(
			output,
			modules: modules,
			samples: ["ScreenA", "ScreenB"].map { DifferentialValueSample(type: "\($0).ForwardedProperties", expression: "7") },
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func retention_passUpKeepsOnlyItsPlacesReads_whenPassedUpPlacesSitAtTwoDepths() async throws {
		let modules = CarrierCells.modules(
			seam: [
				"public protocol Api {}",
				seamFixtureType(named: "First", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Second", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Detail", isFinalClass: true, declarations: ["@Forwarded let id: Int", "@Instantiated let second: Second", "@Instantiated let api: any Api"]),
				seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: [
					"@Instantiated let first: First",
					"@Instantiated let api: any Api",
					"@Instantiated let detailBuilder: Instantiator<Detail>",
				]),
				seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let innerBuilder: Instantiator<Inner>"]),
			],
			app: [Self.apiImpl(reading: "first: First"), CarrierCellRoot.structRoot.declaration(building: "home: Home")],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		try await CarrierCells.expectValuesAndRetentionEqualInlineBuild(
			output,
			modules: modules,
			samples: [DifferentialValueSample(type: "Detail.ForwardedProperties", expression: "7")],
			filesToDelete: &filesToDelete,
		)
	}

	// MARK: Cases

	/// The wrapper the first place of `Api` is held in. A `Sendable` wrapper puts the place in the `@Sendable` family, whose
	/// levels carry no values, so its fill cannot read the level’s value and has no retention to judge here.
	enum PlaceWrapper: CaseIterable, CustomTestStringConvertible, Sendable {
		case erasedInstantiator
		case lazilyInstantiated

		var declaration: String {
			switch self {
			case .erasedInstantiator: "@Instantiated(fulfilledByType: \"ApiImpl\") let apiBuilder: ErasedInstantiator<(), any Api>"
			case .lazilyInstantiated: "@Instantiated let api: LazilyInstantiated<any Api>"
			}
		}

		var testDescription: String {
			switch self {
			case .erasedInstantiator: "an ErasedInstantiator"
			case .lazilyInstantiated: "a LazilyInstantiated"
			}
		}
	}

	/// Where the wrapped place sits: on the level that binds both values, or on a child built beneath it.
	enum PlacePosition: CaseIterable, CustomTestStringConvertible, Sendable {
		case sibling
		case child

		var testDescription: String {
			switch self {
			case .sibling: "beside the sibling place"
			case .child: "on a child beneath the level"
			}
		}
	}

	// MARK: Fixtures

	private static let screenSamples = [DifferentialValueSample(type: "Screen.ForwardedProperties", expression: "7")]

	/// `Screen`, built by `Home` through an instantiator, binds `First` and `Second`, then a place of `Logger` whose
	/// fill reads `Second`, and a place of `Api`, held in `wrapper`, whose fill reads `First`.
	private static func siblingSeam(wrapper: PlaceWrapper, position: PlacePosition) -> [String] {
		var types = [
			"public protocol Api {}",
			"public protocol Logger {}",
			seamFixtureType(named: "First", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Second", isFinalClass: true, declarations: []),
		]
		let wrapperHolder: String
		switch position {
		case .sibling:
			wrapperHolder = wrapper.declaration
		case .child:
			types.append(seamFixtureType(named: "Panel", isFinalClass: true, declarations: [wrapper.declaration]))
			wrapperHolder = "@Instantiated let panel: Panel"
		}
		types.append(seamFixtureType(named: "Screen", isFinalClass: true, declarations: [
			"@Forwarded let id: Int",
			"@Instantiated let first: First",
			"@Instantiated let second: Second",
			"@Instantiated let logger: any Logger",
			wrapperHolder,
		]))
		types.append(seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let screenBuilder: Instantiator<Screen>"]))
		return types
	}

	private static func apiImpl(reading declarations: String...) -> String {
		CarrierCells.fulfillingImpl(named: "ApiImpl", fulfilling: "Api", reading: declarations.map { "@Received let \($0)" })
	}

	private static func loggerImpl(reading declarations: String...) -> String {
		CarrierCells.fulfillingImpl(named: "LoggerImpl", fulfilling: "Logger", reading: declarations.map { "@Received let \($0)" })
	}

	private var filesToDelete: [URL]
}

// MARK: - CarrierCells

/// What the carrier cells of `SafeDIToolSeamCarrier…Tests` share.
enum CarrierCells {
	/// A seam module, `Seam`, holding `seam`'s declarations, and a calling module, `App`, of the same package, whose files
	/// import it.
	static func modules(seam: [String], app: [String], seamConfiguration: [String: String] = [:]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Seam", packageName: "pkg", swiftFileContent: seam, swiftFileContentByFilePath: seamConfiguration),
			ModuleFixture(name: "App", packageName: "pkg", swiftFileContent: app.map { "import Seam\n\n" + $0 }, dependencies: ["Seam"]),
		]
	}

	/// `name`, a type of the calling module that fulfills `protocolName` with `declarations`.
	static func fulfillingImpl(named name: String, fulfilling protocolName: String, reading declarations: [String]) -> String {
		seamFixtureType(named: name, isFinalClass: true, declarations: declarations, conformances: ", \(protocolName)")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [(any \(protocolName)).self])\n")
	}

	/// `modules` with no type declared a seam, so every tree is built inline.
	static func inlineModules(_ modules: [ModuleFixture]) -> [ModuleFixture] {
		modules.map { module in
			ModuleFixture(
				name: module.name,
				packageName: module.packageName,
				swiftFileContent: inlineFixture(module.swiftFileContent),
				swiftFileContentByFilePath: module.swiftFileContentByFilePath.mapValues { inlineFixture([$0])[0] },
				dependencies: module.dependencies,
			)
		}
	}

	/// Expects `output`, the run of `modules`, to build the values the same graph built inline builds for `Root()`, and
	/// to keep alive no more of them than the inline build keeps once the root is released, holding each wrapper the
	/// root's value holds and what one call of it builds, calling an instantiator that forwards a value with the sample of
	/// its type `samples` holds.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	static func expectValuesAndRetentionEqualInlineBuild(
		_ output: MultiModuleTestOutput,
		modules: [ModuleFixture],
		samples: [DifferentialValueSample] = [],
		filesToDelete: inout [URL],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		guard compileVerificationIsEnabled else { return }
		let inlineModules = inlineModules(modules)
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		let graph = try DifferentialValueGraph(
			name: "carrier cell",
			feature: DifferentialValuePath(output: output, modules: modules),
			knownRight: DifferentialValuePath(output: inlineOutput, modules: inlineModules),
			probes: [DifferentialValueProbe("Root()")],
			samples: samples,
			judgesRetention: true,
		)
		let comparison = try #require(try await DifferentialValueOracle.compare(graphs: [graph], filesToDelete: &filesToDelete)?.first?.result.get(), sourceLocation: sourceLocation)
		#expect(comparison.differences == [], sourceLocation: sourceLocation)
		#expect(comparison.retentionDifferences == [], sourceLocation: sourceLocation)
		#expect(comparison.retentionJudgedProbes == ["Root()"], sourceLocation: sourceLocation)
	}

	/// Expects `generatedFiles` to equal `expected`, recording the files generated when they do not, so a failure shows
	/// the output in full.
	static func expectGeneratedFiles(_ generatedFiles: [String: String]?, _ expected: [String: String], sourceLocation: SourceLocation = #_sourceLocation) {
		#expect(generatedFiles == expected, sourceLocation: sourceLocation)
		if let generatedFiles, generatedFiles != expected {
			Issue.record(Comment(rawValue: generatedFiles.sorted { $0.key < $1.key }.map { "=== \($0.key)\n\($0.value)" }.joined(separator: "\n")), sourceLocation: sourceLocation)
		}
	}
}

/// The isolation each of the two modules' declarations default to: the main actor, or none.
struct CarrierCellIsolation: CustomTestStringConvertible, Sendable {
	static let allCases = [
		CarrierCellIsolation(seamModuleIsMainActorByDefault: true, callingModuleIsMainActorByDefault: true),
		CarrierCellIsolation(seamModuleIsMainActorByDefault: true, callingModuleIsMainActorByDefault: false),
		CarrierCellIsolation(seamModuleIsMainActorByDefault: false, callingModuleIsMainActorByDefault: true),
		CarrierCellIsolation(seamModuleIsMainActorByDefault: false, callingModuleIsMainActorByDefault: false),
	]

	let seamModuleIsMainActorByDefault: Bool
	let callingModuleIsMainActorByDefault: Bool

	var seamModuleSettings: VerificationCompilerSettings {
		VerificationCompilerSettings(defaultIsolation: seamModuleIsMainActorByDefault ? "MainActor" : nil, prependsSafeDIImport: false)
	}

	var callingModuleSettings: VerificationCompilerSettings {
		VerificationCompilerSettings(defaultIsolation: callingModuleIsMainActorByDefault ? "MainActor" : nil, prependsSafeDIImport: false)
	}

	var testDescription: String {
		"Seam \(seamModuleIsMainActorByDefault ? "on the main actor" : "nonisolated") by default, App \(callingModuleIsMainActorByDefault ? "on the main actor" : "nonisolated") by default"
	}
}

/// The root that builds the seam: a struct, a class on the main actor, or a `nonisolated` class whose generated
/// initializer `generatedAttributes` puts on the main actor.
enum CarrierCellRoot: CaseIterable, CustomTestStringConvertible, Sendable {
	case structRoot
	case mainActorClassRoot
	case attributedNonisolatedRoot

	/// The root's declaration, which instantiates `property` (`home: Home`).
	func declaration(building property: String) -> String {
		let label = String(property.prefix { $0 != ":" })
		let type = property.drop { $0 != ":" }.dropFirst().trimmingCharacters(in: .whitespaces)
		switch self {
		case .structRoot:
			return """
			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(\(label): \(type)) { self.\(label) = \(label) }
			    @Instantiated let \(label): \(type)
			}
			"""
		case .mainActorClassRoot:
			return """
			@MainActor
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(\(label): \(type)) { self.\(label) = \(label) }
			    @Instantiated let \(label): \(type)
			}
			"""
		case .attributedNonisolatedRoot:
			return """
			@Instantiable(isRoot: true, generatedAttributes: "@MainActor")
			nonisolated public final class Root: Instantiable {
			    @MainActor public init(\(label): \(type)) { self.\(label) = \(label) }
			    @Instantiated let \(label): \(type)
			}
			"""
		}
	}

	/// The declaration of the initializer SafeDI generates for the root, which its kind decides.
	var generatedInitializerDeclaration: String {
		switch self {
		case .structRoot: "public init()"
		case .mainActorClassRoot: "public convenience init()"
		case .attributedNonisolatedRoot: "@MainActor public convenience init()"
		}
	}

	var testDescription: String {
		switch self {
		case .structRoot: "a struct root"
		case .mainActorClassRoot: "a @MainActor class root"
		case .attributedNonisolatedRoot: "a nonisolated class root whose generated initializer is on the main actor"
		}
	}
}
