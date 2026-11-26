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
@testable import SafeDIToolTestSupport

/// The roll of one type built at two places (`GraphFuzzerPlacesOfOneTypeGraph`): each seed's graph builds `Shared` at two
/// places that differ by override, hole level and cycle lap, and every place must get its own value, which a hand-built
/// root states. It judges a generator that shares builder functions per type – across a mock's places, a seam's places,
/// and a cycle's laps – against the values each place is due.
struct SafeDIToolGraphFuzzerPlacesOfOneTypeTests: ~Copyable {
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
	func draw_drawsEachAxisInTenGraphs_whenTheRollIsDrawn() {
		// Each axis stands in for unit tests of its shape only while the roll draws it in ten graphs or more.
		let graphs = Self.seeds.map(GraphFuzzerPlacesOfOneTypeGraph.init(seed:))
		#expect(graphs.count(where: \.isInSeam) >= 10)
		#expect(graphs.count(where: { !$0.isInSeam }) >= 10)
		#expect(graphs.count(where: { $0.branches.contains(where: \.endsInLap) }) >= 10)
		#expect(graphs.count(where: { $0.branches.contains(where: \.isHeldInInstantiator) }) >= 10)
		#expect(graphs.count(where: { $0.branches.allSatisfy { $0.tokenLevel != nil } }) >= 10)
		#expect(graphs.count(where: { $0.branches.contains { $0.tokenLevel == nil } }) >= 10)
		#expect(graphs.count(where: { $0.branches.allSatisfy { $0.override != .none } }) >= 10)
		#expect(graphs.count(where: \.mergingPlacesChangesMockValues) >= 10)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func roll_buildsEachPlacesOwnValue_whenOneTypeIsBuiltAtTwoPlaces() async throws {
		var valueGraphs = [DifferentialValueGraph]()
		var rejections = [String]()
		for graph in Self.seeds.map(GraphFuzzerPlacesOfOneTypeGraph.init(seed:)) {
			do {
				try await valueGraphs.append(Self.valueGraph(of: graph, probePairs: graph.probePairs, filesToDelete: &filesToDelete))
			} catch {
				rejections.append("seed \(graph.seed): \(error)")
			}
		}
		// The draw makes only graphs a person can write, so the tool accepts every one.
		#expect(rejections.isEmpty, "\(rejections.joined(separator: "\n\n"))")
		guard let comparisons = try await DifferentialValueOracle.compare(graphs: valueGraphs, filesToDelete: &filesToDelete) else { return }
		for comparison in comparisons {
			switch comparison.result {
			case let .success(result):
				for difference in result.differences {
					Issue.record("\(comparison.name) builds other values than its places are due: \(difference)\n\(result.report)")
				}
			case let .failure(error):
				Issue.record("\(comparison.name) could not be compared: \(error)")
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func roll_reportsOtherValues_whenAMockMergesThePlacesOverrides() async throws {
		// The roll fires on a merge: a mock that hands every place of `Shared` the first branch's override, as one builder
		// keyed by type would, builds other values wherever the two places' overrides differ. Here the mock's known-right
		// function merges the places, so each seed whose draw separates them must report a difference.
		var valueGraphs = [DifferentialValueGraph]()
		for graph in Self.seeds.map(GraphFuzzerPlacesOfOneTypeGraph.init(seed:)) where graph.mergingPlacesChangesMockValues {
			let mockPair = graph.probePairs[1]
			let mergedPair = DifferentialValueProbePair(name: mockPair.name, featureExpression: mockPair.featureExpression, knownRightExpression: "\(graph.prefix)knownRightMockMergingPlaces()")
			try await valueGraphs.append(Self.valueGraph(of: graph, probePairs: [mergedPair], filesToDelete: &filesToDelete))
		}
		#expect(valueGraphs.count >= 10)
		guard let comparisons = try await DifferentialValueOracle.compare(graphs: valueGraphs, filesToDelete: &filesToDelete) else { return }
		for comparison in comparisons {
			switch comparison.result {
			case let .success(result):
				#expect(!result.differences.isEmpty, "\(comparison.name) does not tell its places apart from a mock that merges them")
			case let .failure(error):
				Issue.record("\(comparison.name) could not be compared: \(error)")
			}
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The roll's seeds. `SAFEDI_PLACES_OF_ONE_TYPE_STARTING_SEED` and `SAFEDI_PLACES_OF_ONE_TYPE_ITERATIONS` explore others.
	private static var seeds: [UInt64] {
		let environment = ProcessInfo.processInfo.environment
		let start = environment["SAFEDI_PLACES_OF_ONE_TYPE_STARTING_SEED"].flatMap(UInt64.init) ?? 0
		let count = environment["SAFEDI_PLACES_OF_ONE_TYPE_ITERATIONS"].flatMap(UInt64.init) ?? 60
		return Array(start..<(start + count))
	}

	/// Runs the tool over `graph`, which compiles its generated code, and returns its graph of `probePairs` in one path.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func valueGraph(of graph: GraphFuzzerPlacesOfOneTypeGraph, probePairs: [DifferentialValueProbePair], filesToDelete: inout [URL]) async throws -> DifferentialValueGraph {
		let path: DifferentialValuePath
		if graph.isInSeam {
			let modules = [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: graph.featureFiles),
				ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: graph.appFiles, dependencies: ["Feature"]),
			]
			let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
			path = try DifferentialValuePath(output: output, modules: modules)
		} else {
			let output = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: graph.allFiles, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
			path = try DifferentialValuePath(fixtureFiles: graph.allFiles, generatedFiles: #require(output.generatedFiles))
		}
		return DifferentialValueGraph(name: "seed \(graph.seed)", path: path, probePairs: probePairs)
	}
}
