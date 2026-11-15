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

// SPIKE: one function per type. Compares the per-path emitter with the per-type emitter over a fuzzer corpus: each
// accepted graph is generated per path (the process runs with `SAFEDI_PER_PATH_EMISSION=1`), and the per-type text is
// the emitter's own pass applied to that output (`PerTypeEmission.transformGeneratedFile`). Where the text differs, the
// two are compiled and their values and retention compared (`DifferentialValueOracle`); every graph is also checked
// for an idempotent pass (a second pass shares nothing more: every key with two places left is a recorded
// not-shared case).
//
// SAFEDI_SPIKE_CORPUS=<first>-<end> (end exclusive) and SAFEDI_SPIKE_CORPUS_FEATURES (empty for the base corpus, or a
// generator feature such as generateDependencyTree) select the graphs; SAFEDI_SPIKE_CORPUS_REPORT names a file each
// graph appends one line to.

import Foundation
import SafeDICore
import Testing
@testable import SafeDIToolTestSupport

struct SpikePerTypeCorpusTests {
	static var seedRange: Range<UInt64>? {
		guard let value = ProcessInfo.processInfo.environment["SAFEDI_SPIKE_CORPUS"],
		      ProcessInfo.processInfo.environment["SAFEDI_PER_PATH_EMISSION"] == "1"
		else { return nil }
		let parts = value.split(separator: "-").compactMap { UInt64($0) }
		guard parts.count == 2, parts[0] < parts[1] else { return nil }
		return parts[0]..<parts[1]
	}

	@Test(.enabled(if: seedRange != nil, "Set SAFEDI_SPIKE_CORPUS and SAFEDI_PER_PATH_EMISSION=1 to run"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func perTypeEmission_buildsTheValuesPerPathEmissionBuilds_overCorpus() async throws {
		let seeds = try #require(Self.seedRange)
		let environment = ProcessInfo.processInfo.environment
		let features = Set((environment["SAFEDI_SPIKE_CORPUS_FEATURES"] ?? "").split(separator: ",").compactMap { GraphFuzzerGeneratorFeature(rawValue: String($0)) })
		let textOnly = environment["SAFEDI_SPIKE_CORPUS_TEXT_ONLY"] == "1"
		let reportPath = environment["SAFEDI_SPIKE_CORPUS_REPORT"]
		func report(_ line: String) {
			guard let reportPath else { return }
			let data = Data((line + "\n").utf8)
			if let handle = FileHandle(forWritingAtPath: reportPath) {
				handle.seekToEndOfFile()
				handle.write(data)
				try? handle.close()
			} else {
				FileManager.default.createFile(atPath: reportPath, contents: data)
			}
		}
		var graphs = [DifferentialValueGraph]()
		var filesToDelete = [URL]()
		defer {
			for file in filesToDelete {
				try? FileManager.default.removeItem(at: file)
			}
		}
		func compareBatch() async throws {
			guard !graphs.isEmpty else { return }
			let comparisons = try await DifferentialValueOracle.compare(graphs: graphs, filesToDelete: &filesToDelete) ?? []
			for comparison in comparisons {
				switch comparison.result {
				case let .success(result):
					let differences = result.differences
					let retention = result.retentionDifferences
					report("compared \(comparison.name) differences=\(differences.count) retentionDifferences=\(retention.count) retentionJudgedProbes=\(result.retentionJudgedProbes.count)")
					for difference in differences {
						report("  difference \(comparison.name): \(difference)")
					}
					for difference in retention {
						report("  retention \(comparison.name): \(difference)")
					}
					if !differences.isEmpty || !retention.isEmpty {
						Issue.record("Seed \(comparison.name): per-type emission builds other values or retains more\n\(result.report)")
					}
				case let .failure(error):
					report("error \(comparison.name): \(String(describing: error).prefix(4_000).replacingOccurrences(of: "\n", with: "\\n"))")
					Issue.record("Seed \(comparison.name): \(error)")
				}
			}
			graphs.removeAll()
		}
		for seed in seeds {
			let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: features)
			let outcome = try await GraphFuzzerOracle.toolOutcome(of: fixture)
			guard case let .accepted(generatedFiles, _) = outcome else {
				report("rejected \(seed)")
				continue
			}
			if textOnly {
				// The emitter itself, run with per-type emission on: every file but a root's `init()` body must be the
				// per-path text, and a root's must be the pass's.
				unsetenv("SAFEDI_PER_PATH_EMISSION")
				let emitted = try await GraphFuzzerOracle.toolOutcome(of: fixture)
				setenv("SAFEDI_PER_PATH_EMISSION", "1", 1)
				guard case let .accepted(emittedFiles, _) = emitted else {
					report("emitterRejects \(seed)")
					Issue.record("Seed \(seed): the per-type emitter rejects a graph the per-path emitter accepts")
					continue
				}
				let differing = Set(emittedFiles.keys).union(generatedFiles.keys).sorted().filter { emittedFiles[$0] != generatedFiles[$0] }
				let disagreeing = Set(emittedFiles.keys).union(generatedFiles.keys).sorted().filter { emittedFiles[$0] != generatedFiles[$0].map(PerTypeEmission.transformGeneratedFile) }
				report("emitted \(seed) filesChanged=\(differing.count) disagreeWithPass=\(disagreeing.joined(separator: ","))")
				if !disagreeing.isEmpty {
					Issue.record("Seed \(seed): the emitter changed \(disagreeing) other than its pass does")
				}
			}
			let perTypeFiles = generatedFiles.mapValues(PerTypeEmission.transformGeneratedFile)
			if let dumpDirectory = environment["SAFEDI_SPIKE_CORPUS_DUMP"] {
				let base = URL(fileURLWithPath: dumpDirectory).appendingPathComponent("\(seed)")
				try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
				for (name, text) in generatedFiles {
					let fileName = URL(fileURLWithPath: name).lastPathComponent
					try text.write(to: base.appendingPathComponent("perPath-" + fileName), atomically: true, encoding: .utf8)
					try (perTypeFiles[name] ?? "").write(to: base.appendingPathComponent("perType-" + fileName), atomically: true, encoding: .utf8)
				}
			}
			let again = perTypeFiles.mapValues(PerTypeEmission.transformGeneratedFile)
			if again != perTypeFiles {
				report("notIdempotent \(seed)")
				Issue.record("Seed \(seed): a second pass shares more")
			}
			let changedFiles = perTypeFiles.keys.sorted().filter { perTypeFiles[$0] != generatedFiles[$0] }
			let linesBefore = generatedFiles.values.reduce(0) { $0 + $1.split(separator: "\n").count }
			let linesAfter = perTypeFiles.values.reduce(0) { $0 + $1.split(separator: "\n").count }
			guard !changedFiles.isEmpty else {
				report("unchanged \(seed) lines=\(linesBefore)")
				continue
			}
			report("changed \(seed) lines=\(linesBefore)->\(linesAfter) files=\(changedFiles.joined(separator: ","))")
			if textOnly {
				continue
			}
			graphs.append(DifferentialValueGraph(
				name: "\(seed)",
				feature: DifferentialValuePath(fixture: fixture, generatedFiles: perTypeFiles),
				knownRight: DifferentialValuePath(fixture: fixture, generatedFiles: generatedFiles),
				probes: fixture.differentialValueProbes(generatedFiles: generatedFiles),
				judgesRetention: true,
			))
			if graphs.count >= 20 {
				try await compareBatch()
			}
		}
		try await compareBatch()
	}
}
