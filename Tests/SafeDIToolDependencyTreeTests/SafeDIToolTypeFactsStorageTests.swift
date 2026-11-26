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
#if os(Linux)
	import Synchronization
#endif
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

		// About 29 elements per node and edge at four layers and at eight: each edge's facts are eight, each binding's
		// eleven, and every node binds its children.
		#expect(elementsPerNodeAndEdge.allSatisfy { $0 <= 32 }, "\(elementsPerNodeAndEdge)")
		#expect(elementsPerNodeAndEdge[1] <= elementsPerNodeAndEdge[0], "\(elementsPerNodeAndEdge)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_buildsTypeFactsGraphWithinFixedAllocationsAndRetainsPerNodeAndEdge_whenWorldIsLifelikeOrHubDoublesItsPaths() async throws {
		// Section 15: the graph's build allocates and retains a small constant per node and edge, never per path, and
		// holds only flat columns: no array inside a column's elements. Allocations and retains are counted through the
		// runtime's instrumentation hooks (`_swift_allocObject`, `_swift_retain`) on the thread that builds the graph; where
		// the runtime has none, only what the graph holds is checked.
		var reports = [try await report(ofRoot: "Root", in: Self.lifelikeFixture)]
		for layerCount in [6, 12] {
			reports.append(try await report(ofRoot: "Root", in: Self.hubFixture(layerCount: layerCount)))
		}
		var perElement = [(allocations: Double, retains: Double)]()
		for report in reports {
			let elements = Double(report.nodes.count + report.edgeCount)
			let root = report.graph.graph.nodes[0].scope
			let counts = RuntimeCounts.counting {
				_ = TypeFactsGraph(root: root, forMockGeneration: report.forMockGeneration)
			}
			if let counts {
				perElement.append((Double(counts.allocations) / elements, Double(counts.retains) / elements))
			}
			try Self.expectFlatColumns(of: report.graph)
		}
		if perElement.count == reports.count {
			// A debug build measured 66, 41 and 35 allocations and 1,163, 919 and 908 retains per node and edge: the
			// interning of properties and types hashes their spellings, which retains each part. The bounds stop growth.
			for (allocations, retains) in perElement {
				#expect(allocations <= 80, "\(perElement)")
				#expect(retains <= 1_400, "\(perElement)")
			}
			// The hub of 12 layers holds 64 times the paths of 6 layers, and no more per node and edge.
			#expect(perElement[2].allocations <= perElement[1].allocations * 1.1, "\(perElement)")
			#expect(perElement[2].retains <= perElement[1].retains * 1.1, "\(perElement)")
		}
	}

	@Test
	func foldFiles_nameNoPropertyTypeOrText_whenReadAsSource() throws {
		// The folds work on IDs and bit sets: `Property`, `TypeDescription` and `String` appear only where the graph is
		// built and where text is spelled, in other files.
		let directory = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent("Sources/SafeDICore/Generators/TypeFacts")
		for file in ["OrderedGraph.swift", "ReadsFromAbove.swift", "SiblingOrder.swift", "TypeFactsColumns.swift"] {
			let source = try String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8)
			let code = source.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
			for name in ["Property", "TypeDescription", "String"] {
				#expect(code.range(of: "\\b\(name)\\b", options: .regularExpression) == nil, "\(file) names \(name)")
			}
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
	/// records, their lookup and the spellings, which text alone reads, hold more.
	private static func expectFlatColumns(of graph: TypeFactsGraph) throws {
		let spellings: Set = ["graph.nodes", "graph.indexByNode", "readTable", "labelTexts", "propertyTable", "typeTable", "moduleNames", "declarationLocations"]
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

/// The allocations and retains the runtime makes on one thread while a body runs, counted through its instrumentation
/// hooks.
private enum RuntimeCounts {
	#if os(Linux)
		typealias AllocateObject = @convention(c) (UnsafeRawPointer?, Int, Int) -> UnsafeMutableRawPointer?
		typealias Retain = @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?

		static let countingThread = Atomic<UInt>(0)
		static let allocations = Atomic<Int>(0)
		static let retains = Atomic<Int>(0)
		static let originalAllocateObject = Atomic<UInt>(0)
		static let originalRetain = Atomic<UInt>(0)

		/// The counts while `body` runs, or `nil` where the runtime has no hooks.
		static func counting(_ body: () -> Void) -> (allocations: Int, retains: Int)? {
			let handle = dlopen(nil, RTLD_NOW)
			guard let enable = dlsym(handle, "_swift_enableSwizzlingOfAllocationAndRefCountingFunctions_forInstrumentsOnly"),
			      let allocateHook = dlsym(handle, "_swift_allocObject"),
			      let retainHook = dlsym(handle, "_swift_retain")
			else { return nil }
			let allocatePointer = allocateHook.assumingMemoryBound(to: AllocateObject.self)
			let retainPointer = retainHook.assumingMemoryBound(to: Retain.self)
			let enablePointer = enable.assumingMemoryBound(to: Bool.self)
			originalAllocateObject.store(UInt(bitPattern: unsafeBitCast(allocatePointer.pointee, to: Int.self)), ordering: .sequentiallyConsistent)
			originalRetain.store(UInt(bitPattern: unsafeBitCast(retainPointer.pointee, to: Int.self)), ordering: .sequentiallyConsistent)
			allocations.store(0, ordering: .sequentiallyConsistent)
			retains.store(0, ordering: .sequentiallyConsistent)
			countingThread.store(UInt(pthread_self()), ordering: .sequentiallyConsistent)
			let wasEnabled = enablePointer.pointee
			let original = (allocatePointer.pointee, retainPointer.pointee)
			allocatePointer.pointee = { metadata, size, alignmentMask in
				if RuntimeCounts.countingThread.load(ordering: .relaxed) == UInt(pthread_self()) {
					RuntimeCounts.allocations.add(1, ordering: .relaxed)
				}
				let original = unsafeBitCast(Int(bitPattern: RuntimeCounts.originalAllocateObject.load(ordering: .relaxed)), to: AllocateObject.self)
				return original(metadata, size, alignmentMask)
			}
			retainPointer.pointee = { object in
				if RuntimeCounts.countingThread.load(ordering: .relaxed) == UInt(pthread_self()) {
					RuntimeCounts.retains.add(1, ordering: .relaxed)
				}
				let original = unsafeBitCast(Int(bitPattern: RuntimeCounts.originalRetain.load(ordering: .relaxed)), to: Retain.self)
				return original(object)
			}
			enablePointer.pointee = true
			body()
			countingThread.store(0, ordering: .sequentiallyConsistent)
			enablePointer.pointee = wasEnabled
			allocatePointer.pointee = original.0
			retainPointer.pointee = original.1
			return (allocations.load(ordering: .sequentiallyConsistent), retains.load(ordering: .sequentiallyConsistent))
		}
	#else
		/// The counts while `body` runs, or `nil` where the runtime has no hooks: this platform's runtime keeps them for
		/// Instruments alone.
		static func counting(_ body: () -> Void) -> (allocations: Int, retains: Int)? {
			body()
			return nil
		}
	#endif
}
