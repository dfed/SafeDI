import Foundation
import Testing

@testable import SafeDIToolTestSupport

/// Local exploration only: prints, for each seed in SAFEDI_EXPLORE_LOOP_SEEDS, whether this tree's generated code for
/// the release acceptance fixture shows a loop through received instantiators (#649's signature).
struct ExplorationLoopFeatureTests {
	@Test(.enabled(if: ProcessInfo.processInfo.environment["SAFEDI_EXPLORE_LOOP_SEEDS"] != nil))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func printLoopFeatures() async throws {
		let seeds = (ProcessInfo.processInfo.environment["SAFEDI_EXPLORE_LOOP_SEEDS"] ?? "").split(separator: ",").compactMap { UInt64($0) }
		let loopFeatures: Set<GraphFuzzerFeature> = [.buildersReceivingEachOther, .sendableBuildersReceivingEachOther, .builderReceivedInsideItsTree, .sendableBuilderReceivedInsideItsTree, .receivedLoopMemberWithCycleParameters, .sendableReceivedLoopMemberWithCycleParameters]
		var lines = [String]()
		for seed in seeds {
			let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, storingEveryParameter: true)
			let outcome = try await GraphFuzzerOracle.toolOutcome(of: fixture)
			let found = GraphFuzzerFeature.features(of: fixture, outcome: outcome).intersection(loopFeatures).map { "\($0)" }.sorted()
			lines.append("loop \(seed) \(found.joined(separator: ","))")
		}
		try lines.joined(separator: "\n").write(toFile: ProcessInfo.processInfo.environment["SAFEDI_EXPLORE_LOOP_REPORT"] ?? "/dev/stdout", atomically: false, encoding: .utf8)
	}

	@Test(.enabled(if: ProcessInfo.processInfo.environment["SAFEDI_EXPLORE_DUMP_SEEDS"] != nil))
	func dumpReleaseAcceptanceFixtures() throws {
		let environment = ProcessInfo.processInfo.environment
		let seeds = (environment["SAFEDI_EXPLORE_DUMP_SEEDS"] ?? "").split(separator: ",").compactMap { UInt64($0) }
		let root = URL(fileURLWithPath: environment["SAFEDI_EXPLORE_DUMP_DIRECTORY"] ?? "")
		for seed in seeds {
			let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, storingEveryParameter: true)
			let directory = root.appendingPathComponent("\(seed)")
			try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
			for (name, content) in zip(fixture.fileNames, fixture.swiftFileContent) {
				try content.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
			}
		}
	}
}

/// Local exploration only: runs the modules under SAFEDI_EXPLORE_MM_DIRECTORY (one directory per module, listed in
/// order.txt, each with dependencies.txt) under both integrations and writes each module's generated files to
/// SAFEDI_EXPLORE_MM_OUTPUT/<integration>/<module>/.
struct ExplorationMultiModuleTests {
	@Test(.enabled(if: ProcessInfo.processInfo.environment["SAFEDI_EXPLORE_MM_DIRECTORY"] != nil))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func writeBothIntegrations() async throws {
		let environment = ProcessInfo.processInfo.environment
		let root = URL(fileURLWithPath: environment["SAFEDI_EXPLORE_MM_DIRECTORY"] ?? "")
		let output = URL(fileURLWithPath: environment["SAFEDI_EXPLORE_MM_OUTPUT"] ?? "")
		let order = try String(contentsOf: root.appendingPathComponent("order.txt"), encoding: .utf8).split(whereSeparator: \.isNewline).map(String.init)
		var modules = [ModuleFixture]()
		for name in order {
			let directory = root.appendingPathComponent(name)
			let dependenciesFile = directory.appendingPathComponent("dependencies.txt")
			let dependencies = (try? String(contentsOf: dependenciesFile, encoding: .utf8))?.split(whereSeparator: \.isNewline).map(String.init) ?? []
			var files = [String: String]()
			for file in try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() where file.hasSuffix(".swift") {
				files[file] = try String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8)
			}
			modules.append(ModuleFixture(name: name, packageName: "Fuzz", swiftFileContentByFilePath: files, dependencies: dependencies))
		}
		for integration in MultiModuleIntegration.allCases {
			var filesToDelete = [URL]()
			defer { for file in filesToDelete { try? FileManager.default.removeItem(at: file) } }
			let result = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: integration, compileVerification: .returningOutcomeOnly, modulesBeneath: environment["SAFEDI_EXPLORE_MM_BENEATH"] == nil ? nil : { $0 }, filesToDelete: &filesToDelete, recordDirectory: nil)
			for (moduleName, moduleOutput) in result.modules {
				let directory = output.appendingPathComponent("\(integration)").appendingPathComponent(moduleName)
				try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
				for (fileName, content) in moduleOutput.generatedFiles {
					try content.write(to: directory.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
				}
			}
			try "\(String(describing: result.compilation))".write(to: output.appendingPathComponent("\(integration)-compilation.txt"), atomically: true, encoding: .utf8)
		}
	}
}

/// Local exploration only: writes seed SAFEDI_EXPLORE_EDIT_SEED's seam graph, drawn and with builder surface edit
/// SAFEDI_EXPLORE_EDIT (a raw value), and the tool's output for each, under SAFEDI_EXPLORE_EDIT_OUTPUT.
struct ExplorationBuilderSurfaceEditTests {
	@Test(.enabled(if: ProcessInfo.processInfo.environment["SAFEDI_EXPLORE_EDIT_SEED"] != nil))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func writeEditedGraph() async throws {
		let environment = ProcessInfo.processInfo.environment
		let seed = UInt64(environment["SAFEDI_EXPLORE_EDIT_SEED"] ?? "") ?? 0
		let output = URL(fileURLWithPath: environment["SAFEDI_EXPLORE_EDIT_OUTPUT"] ?? "")
		let edit = try #require(GraphFuzzerBuilderSurfaceEdit(rawValue: environment["SAFEDI_EXPLORE_EDIT"] ?? ""))
		let fixtures: [(String, GraphFuzzerFixture?)] = [
			("drawn", GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateDependencyTree])),
			("edited", GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateDependencyTree], builderSurfaceEdit: edit)),
		]
		for (name, fixture) in fixtures {
			guard let fixture else { continue }
			let directory = output.appendingPathComponent(name)
			try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
			try fixture.swiftFileContent.joined(separator: "\n// ----\n").write(to: directory.appendingPathComponent("fixture.txt"), atomically: true, encoding: .utf8)
			let outcome = try await GraphFuzzerOracle.toolOutcome(of: fixture)
			try outcome.description.write(to: directory.appendingPathComponent("outcome.txt"), atomically: true, encoding: .utf8)
		}
	}
}
