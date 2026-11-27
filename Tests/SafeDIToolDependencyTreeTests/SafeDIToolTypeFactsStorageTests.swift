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

		// About 39 elements per node and edge at four layers and at eight, every column counted, the variants' and the
		// read and label runs included: each edge's facts are seven, each binding's eleven, and every node binds its
		// children.
		#expect(elementsPerNodeAndEdge.allSatisfy { $0 <= 44 }, "\(elementsPerNodeAndEdge)")
		#expect(elementsPerNodeAndEdge[1] <= elementsPerNodeAndEdge[0], "\(elementsPerNodeAndEdge)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_hidesEachAliasOncePerDeclarationOfItsLabel_whenOneLabelIsDeclaredByManyTypes() async throws {
		// Every `Feature` declares `m`, each of another type, and one tree beneath the first reads `m` through an alias
		// received only if available. A declaration hides the alias of its label, one column, however many properties
		// share the label: the hidden columns grow with the declarations, where hiding every property of the label grew
		// with their square.
		var hiddenColumnCounts = [Int]()
		for featureCount in [8, 32] {
			var types = [seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: (1...featureCount).map { "@Instantiated let feature\($0): Feature\($0)" })]
			for feature in 1...featureCount {
				let declarations = feature == 1
					? ["@Instantiated let m: Model1", "@Instantiated let reader: Reader"]
					: ["@Instantiated let m: Model\(feature)"]
				types.append(seamFixtureType(named: "Feature\(feature)", isFinalClass: true, declarations: declarations))
				types.append(seamFixtureType(named: "Model\(feature)", isFinalClass: true, declarations: []))
			}
			types.append(seamFixtureType(named: "Reader", isFinalClass: true, declarations: [#"@Received(fulfilledByDependencyNamed: "m", ofType: Model1.self, onlyIfAvailable: true) let model: Model1?"#]))
			let report = try await report(ofRoot: "Root", in: types)
			hiddenColumnCounts.append(report.graph.aliasHiddenColumnCount)
		}
		#expect(hiddenColumnCounts == [8, 32])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_hidesEveryAliasOfALabelPerDeclaration_whenEachTypeDeclaringTheLabelAliasesItsOwnProperty() async throws {
		// The case the label hiding leaves quadratic: every `Feature` declares `m` of another type, and a tree beneath each
		// reads its own `m` through an alias received only if available, so the label has as many aliases as declarations
		// and each declaration hides all of them. The move of the facts graph onto the run's IDs owns hiding by label ID.
		var hiddenColumnCounts = [Int]()
		for featureCount in [8, 32] {
			var types = [seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: (1...featureCount).map { "@Instantiated let feature\($0): Feature\($0)" })]
			for feature in 1...featureCount {
				types.append(seamFixtureType(named: "Feature\(feature)", isFinalClass: true, declarations: ["@Instantiated let m: Model\(feature)", "@Instantiated let reader: Reader\(feature)"]))
				types.append(seamFixtureType(named: "Model\(feature)", isFinalClass: true, declarations: []))
				types.append(seamFixtureType(named: "Reader\(feature)", isFinalClass: true, declarations: ["@Received(fulfilledByDependencyNamed: \"m\", ofType: Model\(feature).self, onlyIfAvailable: true) let model: Model\(feature)?"]))
			}
			let report = try await report(ofRoot: "Root", in: types)
			hiddenColumnCounts.append(report.graph.aliasHiddenColumnCount)
		}
		#expect(hiddenColumnCounts == [8 * 8, 32 * 32])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_buildsTypeFactsGraphOfFlatColumns_whenWorldIsLifelikeOrHubDoublesItsPaths() async throws {
		// Section 15: the graph holds only flat columns, no array inside a column's elements, so what its build allocates
		// grows with its elements, which the test above bounds. Allocations and retains are not counted: the runtime's
		// instrumentation hooks (`_swift_allocObject`, `_swift_retain`) take a hook in a register-preserving convention a
		// Swift closure does not keep, which crashed the suite on Swift 6.3 on Linux.
		var reports = await [try report(ofRoot: "Root", in: Self.lifelikeFixture)]
		for layerCount in [6, 12] {
			await reports.append(try report(ofRoot: "Root", in: Self.hubFixture(layerCount: layerCount)))
		}
		for report in reports {
			try Self.expectFlatColumns(of: report.graph)
		}
	}

	private var filesToDelete: [URL]

	/// A root whose tree holds what a real adopter's does: a value shared by its screens, a cycle of screens that open
	/// each other through instantiators, a `Sendable` builder, a lazy value, a rename, and a receive only if available.
	private static let lifelikeFixture = [
		seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let session: Session", "@Instantiated let store: LazilyInstantiated<Store>", "@Instantiated let homeBuilder: Instantiator<Home>", "@Instantiated let worker: SendableInstantiator<Worker>"]),
		seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
		seamFixtureType(named: "Store", isFinalClass: true, declarations: ["@Received let session: Session"]),
		seamFixtureType(named: "Home", isFinalClass: true, declarations: ["@Received let session: Session", "@Received let store: Store", "@Instantiated let detailBuilder: Instantiator<Detail>", "@Received(onlyIfAvailable: true) let banner: Banner?"]),
		seamFixtureType(named: "Detail", isFinalClass: true, declarations: ["@Received let session: Session", "@Instantiated let homeBuilder: Instantiator<Home>", "@Received(fulfilledByDependencyNamed: \"session\", ofType: Session.self) let account: Session"]),
		seamFixtureType(named: "Banner", isFinalClass: true, declarations: []),
		seamFixtureType(named: "Worker", isFinalClass: true, declarations: []),
	]

	/// A root whose layers each build the next twice and receive `session`, so the paths double at each layer.
	private static func hubFixture(layerCount: Int) -> [String] {
		var types = [seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let session: Session", "@Instantiated let layer: Layer1"])]
		for layer in 1...layerCount {
			let declarations = layer == layerCount
				? ["@Received let session: Session"]
				: ["@Received let session: Session", "@Instantiated let first: Layer\(layer + 1)", "@Instantiated let second: Layer\(layer + 1)"]
			types.append(seamFixtureType(named: "Layer\(layer)", isFinalClass: true, declarations: declarations))
		}
		types.append(seamFixtureType(named: "Session", isFinalClass: true, declarations: []))
		return types
	}

	/// The report of the last production tree of `root` the memo oracle observes while `types` are generated.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private func report(ofRoot root: String, in types: [String]) async throws -> TypeFactsReport {
		let (stream, continuation) = AsyncStream.makeStream(of: TypeFactsReport.self)
		_ = try await ConstructionMemoOracle.$observer.withValue({ _, _, report in continuation.yield(report) }) {
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
		for await report in stream where report.root == root && !report.forMockGeneration {
			reports.append(report)
		}
		return try #require(reports.last)
	}

	/// Every column the graph holds is an array whose elements hold no array, set, dictionary or class: only the node
	/// records, their lookup, the spellings, which text alone reads, and the names a mock root's lowering hands the node
	/// records of its world, which no fact reads, hold more.
	private static func expectFlatColumns(of graph: TypeFactsGraph) throws {
		let spellings: Set = [
			"graph.nodes", "graph.indexByNode", "readTable", "labelTexts", "propertyTable", "typeTable", "moduleNames", "declarationLocations",
			// A per-root map that no fold reads.
			"mockRootNames",
		]
		var columnCount = 0
		var stack: [(path: String, value: Any)] = Mirror(reflecting: graph).children.map { ($0.label ?? "", $0.value) }
		while let (path, value) = stack.popLast() {
			guard !spellings.contains(path) else { continue }
			let mirror = Mirror(reflecting: value)
			switch mirror.displayStyle {
			case .collection:
				columnCount += 1
				for element in mirror.children {
					#expect(!holdsReference(element.value), "\(path) holds an element that holds an array, a set, a dictionary or a class")
				}
			case .struct:
				stack.append(contentsOf: mirror.children.map { ("\(path).\($0.label ?? "")", $0.value) })
			case .class, .dictionary, .set:
				Issue.record("\(path) is a \(String(describing: mirror.displayStyle)), not a flat column")
			case .enum, .optional, .tuple, .foreignReference, nil:
				break
			@unknown default:
				Issue.record("\(path) is of a kind this test does not know")
			}
		}
		#expect(columnCount > 0)
	}

	private static func holdsReference(_ value: Any) -> Bool {
		let mirror = Mirror(reflecting: value)
		switch mirror.displayStyle {
		case .collection, .dictionary, .set, .class, .foreignReference:
			return true
		case .struct, .tuple, .enum, .optional:
			return mirror.children.contains { holdsReference($0.value) }
		case nil:
			return false
		@unknown default:
			return true
		}
	}
}
