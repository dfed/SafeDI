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

/// A world's graph of per-type facts keeps its facts in flat columns of 32-bit IDs and bit sets (`TypeFactsGraph`), so
/// what it holds grows with its declarations and edges, never with the paths through them.
struct SafeDIToolTypeFactsStorageTests: ~Copyable {
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
	mutating func generate_keepsTypeFactsColumnsWithinFixedElementsPerNodeAndEdge_whenEveryLayerOfHubDoublesItsPaths() async throws {
		// Each layer builds the next twice and receives `session`, so the paths double at each layer while the graph
		// gains two nodes and four edges. The columns' elements per node and edge stay the same at four layers and at eight.
		var elementsPerNodeAndEdge = [Double]()
		for layerCount in [4, 8] {
			var types = [seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let session: Session", "@Instantiated let layer: Layer1"])]
			for layer in 1...layerCount {
				let declarations = layer == layerCount
					? ["@Received let session: Session"]
					: ["@Received let session: Session", "@Instantiated let first: Layer\(layer + 1)", "@Instantiated let second: Layer\(layer + 1)"]
				types.append(seamFixtureType(named: "Layer\(layer)", isFinalClass: true, declarations: declarations))
			}
			types.append(seamFixtureType(named: "Session", isFinalClass: true, declarations: []))
			let (stream, continuation) = AsyncStream.makeStream(of: TypeFactsReport.self)
			_ = try await ConstructionMemoOracle.$observer.withValue({ _, _, report in continuation.yield(report) }) { [types] in
				var filesToDelete = [URL]()
				defer {
					for file in filesToDelete {
						try? FileManager.default.removeItem(at: file)
					}
				}
				return try await executeSafeDIToolTest(swiftFileContent: types, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete, skipCompileVerification: true)
			}
			continuation.finish()
			var reports = [TypeFactsReport]()
			for await report in stream where report.root == "Root" {
				reports.append(report)
			}
			let report = try #require(reports.last)
			#expect(report.nodes.count == 2 * layerCount + 1)
			#expect(report.places.count == (1 << layerCount) + 1)
			elementsPerNodeAndEdge.append(Double(report.columnElementCount) / Double(report.nodes.count + report.edgeCount))
		}

		// Every column counted, the variants' and the read and label runs included: 302 elements over 9 nodes and 12 edges,
		// then 622 over 17 and 28.
		#expect(elementsPerNodeAndEdge.allSatisfy { $0 <= 15 }, "\(elementsPerNodeAndEdge)")
		#expect(elementsPerNodeAndEdge[1] <= elementsPerNodeAndEdge[0], "\(elementsPerNodeAndEdge)")
	}

	private var filesToDelete: [URL]
}
