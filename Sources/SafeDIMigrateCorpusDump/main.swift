// SPIKE: writes a slice of the graph fuzzer's corpora, each graph's sources and 2.x generated code, for the
// migrate prototype. Never to land. Usage: SafeDIMigrateCorpusDump OUTPUT_DIRECTORY BASE_SEEDS SEAM_SEEDS PUBLIC_SEEDS
import Foundation
@testable import SafeDIToolTestSupport

let arguments = CommandLine.arguments
let outputRoot = arguments[1]
let corpora: [(String, Set<GraphFuzzerGeneratorFeature>, Int)] = [
	("base", [], Int(arguments[2]) ?? 0),
	("seam", [.generateDependencyTree], Int(arguments[3]) ?? 0),
	("public-mock", [.generateMockPublic], Int(arguments[4]) ?? 0),
]
for (name, features, seedCount) in corpora {
	try await withThrowingTaskGroup(of: Void.self) { group in
		var seeds = (0..<UInt64(seedCount)).makeIterator()
		func addNext() {
			guard let seed = seeds.next() else { return }
			group.addTask {
				let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: features)
				let directory = URL(fileURLWithPath: outputRoot).appendingPathComponent(name).appendingPathComponent("\(seed)")
				let sources = directory.appendingPathComponent("sources")
				try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
				for (index, content) in fixture.swiftFileContent.enumerated() {
					try content.write(to: sources.appendingPathComponent(String(format: "%03d.swift", index)), atomically: true, encoding: .utf8)
				}
				let (outcome, _) = try await GraphFuzzerOracle.toolRun(of: fixture)
				switch outcome {
				case let .accepted(generatedFiles, _):
					let generated = directory.appendingPathComponent("generated")
					try FileManager.default.createDirectory(at: generated, withIntermediateDirectories: true)
					for (fileName, contents) in generatedFiles {
						try contents.write(to: generated.appendingPathComponent(fileName.replacingOccurrences(of: "/", with: "__")), atomically: true, encoding: .utf8)
					}
				case .rejected:
					try "".write(to: directory.appendingPathComponent("rejected"), atomically: true, encoding: .utf8)
				}
			}
		}
		for _ in 0..<4 { addNext() }
		while try await group.next() != nil { addNext() }
	}
	print("dumped \(name)")
}
