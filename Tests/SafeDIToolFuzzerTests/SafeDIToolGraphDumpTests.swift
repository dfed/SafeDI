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

/// Writes the fuzzer's graphs to disk, one JSON file per seed, for a differential runner outside the test process to
/// run through two built tools (a rewrite's comparison stream). Nothing runs unless `SAFEDI_GRAPH_DUMP_DIRECTORY` names
/// a directory.
///
/// Each file holds the seed, the flow `GraphFuzzerBaseComparison` runs the graph in, the active compilation conditions,
/// and its modules in dependency order: a graph in one module is one module named `Fuzz` with no package and the plugin
/// flow; a split graph lists each module's name, package (`null` where the module has none), the modules whose `.safedi`
/// it reads, and its files by name, as Bazel's rule runs them.
struct SafeDIToolGraphDumpTests {
	@Test(.enabled(if: ProcessInfo.processInfo.environment["SAFEDI_GRAPH_DUMP_DIRECTORY"] != nil, "Set SAFEDI_GRAPH_DUMP_DIRECTORY to run"))
	func dump_writesEveryGraph_whenEnabledByEnvironment() throws {
		let environment = ProcessInfo.processInfo.environment
		let directory = URL(fileURLWithPath: try #require(environment["SAFEDI_GRAPH_DUMP_DIRECTORY"]))
		let featureNames = (environment["SAFEDI_GRAPH_DUMP_FEATURES"] ?? "").split(separator: ",").map(String.init)
		let features = Set(featureNames.compactMap(GraphFuzzerGeneratorFeature.init(rawValue:)))
		try #require(features.count == featureNames.count, "SAFEDI_GRAPH_DUMP_FEATURES names a feature that does not exist.")
		let startingSeed = try #require(UInt64(environment["SAFEDI_GRAPH_DUMP_STARTING_SEED"] ?? "0"))
		let count = try #require(UInt64(environment["SAFEDI_GRAPH_DUMP_ITERATIONS"] ?? "1"))
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let corpusName = features.isEmpty ? "base" : features.map(\.rawValue).sorted().joined(separator: ",")
		for seed in startingSeed..<(startingSeed + count) {
			let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: features)
			let graph = Self.graph(of: fixture, corpusName: corpusName)
			let data = try JSONSerialization.data(withJSONObject: graph, options: [.sortedKeys])
			try data.write(to: directory.appendingPathComponent("\(corpusName)-\(seed).json"))
		}
	}

	private static func graph(of fixture: GraphFuzzerFixture, corpusName: String) -> [String: Any] {
		let fileNames = fixture.fileNames
		var graph: [String: Any] = [
			"seed": fixture.seed,
			"corpus": corpusName,
			"conditions": fixture.activeCompilationConditions,
		]
		guard let modules = fixture.modules else {
			var usedNames = Set<String>()
			var files = [[String]]()
			for (index, (fileName, content)) in zip(fileNames, fixture.swiftFileContent).enumerated() {
				// As `GraphFuzzerBaseComparison` names them: a second file of one name keeps a name of its own.
				let name = usedNames.insert(fileName).inserted ? fileName : "\(index)_\(fileName.replacingOccurrences(of: "/", with: "_"))"
				usedNames.insert(name)
				files.append([name, content])
			}
			graph["flow"] = "plugin"
			graph["modules"] = [["name": "Fuzz", "package": NSNull(), "dependencies": [String](), "files": files]]
			return graph
		}
		let presentModules = Set(modules)
		let dependencyLists = fixture.dependencyLists(modules: modules, integration: .moduleInfo, listsTransitiveDependencies: false)
		var moduleEntries = [[String: Any]]()
		for module in GraphFuzzerModule.allCases where presentModules.contains(module) {
			var contentByFileName = [String: String]()
			for index in modules.indices where modules[index] == module {
				contentByFileName[fileNames[index]] = fixture.swiftFileContent[index]
			}
			moduleEntries.append([
				"name": module.name,
				"package": fixture.modulesOmittingPackageName.contains(module) ? NSNull() : module.packageName as Any,
				"dependencies": (dependencyLists[module] ?? []).map(\.name),
				"files": contentByFileName.keys.sorted().map { [$0, contentByFileName[$0] ?? ""] },
			])
		}
		graph["flow"] = "module-info"
		graph["modules"] = moduleEntries
		return graph
	}
}
