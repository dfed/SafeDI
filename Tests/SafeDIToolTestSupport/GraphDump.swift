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

/// Writes each multi-module fixture a test runs under the module-info flow to `SAFEDI_GRAPH_DUMP_DIRECTORY`, when it is
/// set, as a JSON graph a differential runner outside the test process runs through two built tools (a rewrite's
/// comparison stream, which so compares every hand-written fixture as well as the fuzzer's graphs). Nothing is written
/// when the variable is unset. A fixture that names its fixture root in its files, which differs per run, is left out.
enum GraphDump {
	static let directory = ProcessInfo.processInfo.environment["SAFEDI_GRAPH_DUMP_DIRECTORY"].map { URL(fileURLWithPath: $0) }

	static func write(_ modules: [WrittenModule], fixtureRoot: URL) throws {
		guard let directory else { return }
		var moduleEntries = [[String: Any]]()
		for module in modules {
			guard module.fixture.runsSafeDI, !module.fixture.isCheckoutPackage, !module.fixture.omitsModuleName, !module.fixture.deletesSwiftFilesAfterRunning else { return }
			var files = [[String]]()
			for (name, file) in zip(module.fileNames, module.swiftFiles) {
				let content = try String(contentsOf: file, encoding: .utf8)
				guard !content.contains(fixtureRoot.path) else { return }
				files.append([name, content])
			}
			moduleEntries.append([
				"name": module.fixture.name,
				"package": module.fixture.omitsPackageName ? NSNull() : module.fixture.packageName as Any,
				"dependencies": module.fixture.dependencies.filter { name in modules.contains { $0.fixture.name == name } },
				"conditions": module.fixture.toolCompilationConditions,
				"files": files,
			])
		}
		let body = try JSONSerialization.data(withJSONObject: moduleEntries, options: [.sortedKeys])
		// FNV-1a: the same graph from two tests is one file.
		let digest = body.reduce(UInt64(0xCBF2_9CE4_8422_2325)) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3 }
		let graph: [String: Any] = [
			"seed": digest,
			"corpus": "suite",
			"test": Test.current?.name ?? "",
			"flow": "module-info",
			"conditions": [String](),
			"modules": moduleEntries,
		]
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		try JSONSerialization.data(withJSONObject: graph, options: [.sortedKeys]).write(to: directory.appendingPathComponent("suite-\(digest).json"))
	}
}
