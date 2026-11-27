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
@testable import SafeDIToolTestSupport

/// The corpora's draw of twins over a shared screen: `addingTwinsOverSharedScreen` in the base and seam corpora, and its
/// public mock form in the public mock corpus.
struct SafeDIToolGraphFuzzerTwinDrawTests {
	@Test(arguments: TwinCorpus.allCases)
	func corpus_drawsEachShapeOfTwinsOverSharedScreen_inPinnedNumberOfGraphs(corpus: TwinCorpus) {
		// Each shape lands in exactly the pinned number of the corpus's graphs, read from their source, and in at least ten:
		// the draw is deterministic, so a change in a shape's share is a reviewed diff.
		var counts = [TwinShape: Int]()
		for seed in 0..<corpus.seedCount {
			for shape in TwinShape.shapes(of: GraphFuzzerGenerator.fixture(forSeed: seed, features: corpus.features)) {
				counts[shape, default: 0] += 1
			}
		}
		for shape in corpus.shapes {
			#expect(counts[shape, default: 0] == corpus.drawnShapeCounts[shape], "\(corpus) \(shape.rawValue) drawn in \(counts[shape, default: 0]) graphs")
			#expect(counts[shape, default: 0] >= SafeDIToolGraphFuzzerTests.gatingDrawJudgedGraphFloor, "\(corpus) \(shape.rawValue) drawn in fewer than ten graphs")
		}
	}

	@Test(arguments: TwinCorpus.allCases)
	func toolRuns_acceptEachShapeOfTwinsOverSharedScreen_inPinnedNumberOfGraphs(corpus: TwinCorpus) async throws {
		// The tool accepts each shape in exactly the pinned number of the corpus's graphs that draw it, and in at least ten,
		// so that the corpus's value oracles compare the twins' values in that many graphs. Another draw of a graph can
		// have the tool reject it, never this one: no error names the draw's types. Where the root holds the twins, the
		// plan sees them in every accepted graph (`PlanBodiesObservation`'s twin values), so `TwinIdentityChecks`, which
		// every graph runs, judges each.
		let drawnSeeds = (0..<corpus.seedCount).filter { !TwinShape.shapes(of: GraphFuzzerGenerator.fixture(forSeed: $0, features: corpus.features)).isEmpty }
		// The seeds run at once, each observed in a task of its own. The observer is set only where the root holds the
		// twins: an observer of the plan has the executors compare every root with its plan, not only those it admits.
		let acceptedShapes = try await withThrowingTaskGroup(of: [TwinShape].self) { group in
			for seed in drawnSeeds {
				group.addTask {
					try await Self.acceptedShapes(ofSeed: seed, in: corpus)
				}
			}
			var acceptedShapes = [TwinShape]()
			for try await shapes in group {
				acceptedShapes.append(contentsOf: shapes)
			}
			return acceptedShapes
		}
		var counts = [TwinShape: Int]()
		for shape in acceptedShapes {
			counts[shape, default: 0] += 1
		}
		for shape in corpus.shapes {
			#expect(counts[shape, default: 0] == corpus.acceptedShapeCounts[shape], "\(corpus) \(shape.rawValue) accepted in \(counts[shape, default: 0]) graphs")
			#expect(counts[shape, default: 0] >= SafeDIToolGraphFuzzerTests.gatingDrawJudgedGraphFloor, "\(corpus) \(shape.rawValue) accepted in fewer than ten graphs")
		}
	}

	/// The shapes `seed`'s graph draws where the tool accepts it, and none where it rejects it.
	private static func acceptedShapes(ofSeed seed: UInt64, in corpus: TwinCorpus) async throws -> [TwinShape] {
		let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: corpus.features)
		let prefix = GraphFuzzerFixture.typeNamePrefix(forSeed: seed)
		let (stream, continuation) = AsyncStream.makeStream(of: String.self)
		let outcome: GraphFuzzerToolOutcome = if corpus.rootHoldsTwins {
			try await PlanBodiesObservation.$observer.withValue({ root, _, _, twinValues in
				if root.hasSuffix("TwinRoot"), !twinValues.isEmpty {
					continuation.yield(root)
				}
			}) {
				try await GraphFuzzerOracle.toolOutcome(of: fixture)
			}
		} else {
			try await GraphFuzzerOracle.toolOutcome(of: fixture)
		}
		continuation.finish()
		var rootsHoldingTwins = 0
		for await _ in stream {
			rootsHoldingTwins += 1
		}
		switch outcome {
		case let .rejected(diagnostics):
			#expect(!diagnostics.contains(prefix + "Twin"), "\(corpus) seed \(seed) is rejected over the draw's types: \(diagnostics)")
			return []
		case .accepted:
			if corpus.rootHoldsTwins {
				#expect(rootsHoldingTwins >= 1, "\(corpus) seed \(seed): the plan sees no twin in TwinRoot")
			}
			return Array(TwinShape.shapes(of: fixture))
		}
	}
}

/// A corpus that draws twins over a shared screen.
enum TwinCorpus: String, CaseIterable, CustomTestStringConvertible {
	case base
	case seam
	case publicMock

	var testDescription: String {
		rawValue
	}

	var features: Set<GraphFuzzerGeneratorFeature> {
		switch self {
		case .base: []
		case .seam: [.generateDependencyTree]
		case .publicMock: [.generateMockPublic]
		}
	}

	var seedCount: UInt64 {
		switch self {
		case .base: UInt64(SafeDIToolGraphFuzzerTests.corpusSeedCount)
		case .seam: UInt64(SafeDIToolGraphFuzzerTests.seamCorpusSeedCount)
		case .publicMock: UInt64(SafeDIToolGraphFuzzerTests.publicMockCorpusSeedCount)
		}
	}

	/// Whether a production root's own tree holds the twins, which the plan then sees; a seam's own tree is built per path.
	var rootHoldsTwins: Bool {
		switch self {
		case .base: true
		case .seam, .publicMock: false
		}
	}

	var shapes: [TwinShape] {
		switch self {
		case .base, .publicMock: TwinShape.allCases.filter { $0 != .inSeam }
		case .seam: TwinShape.allCases
		}
	}

	var drawnShapeCounts: [TwinShape: Int] {
		switch self {
		case .base: [
				.drawn: 187,
				.valueFirst: 93,
				.wrapperFirst: 94,
				.sendableWrapper: 48,
				.screenReceivesOnlyIfAvailable: 67,
				.screenBuildsPanel: 76,
				.firstThroughInstantiator: 91,
				.topOpensSecond: 78,
			]
		case .seam: [
				.drawn: 195,
				.valueFirst: 98,
				.wrapperFirst: 97,
				.sendableWrapper: 57,
				.screenReceivesOnlyIfAvailable: 56,
				.screenBuildsPanel: 73,
				.firstThroughInstantiator: 101,
				.topOpensSecond: 71,
				.inSeam: 195,
			]
		case .publicMock: [
				.drawn: 130,
				.valueFirst: 61,
				.wrapperFirst: 69,
				.sendableWrapper: 22,
				.screenReceivesOnlyIfAvailable: 33,
				.screenBuildsPanel: 46,
				.firstThroughInstantiator: 59,
				.topOpensSecond: 57,
			]
		}
	}

	var acceptedShapeCounts: [TwinShape: Int] {
		switch self {
		case .base: [
				.drawn: 98,
				.valueFirst: 52,
				.wrapperFirst: 46,
				.sendableWrapper: 20,
				.screenReceivesOnlyIfAvailable: 36,
				.screenBuildsPanel: 32,
				.firstThroughInstantiator: 46,
				.topOpensSecond: 44,
			]
		case .seam: [
				.drawn: 50,
				.valueFirst: 27,
				.wrapperFirst: 23,
				.sendableWrapper: 12,
				.screenReceivesOnlyIfAvailable: 17,
				.screenBuildsPanel: 15,
				.firstThroughInstantiator: 27,
				.topOpensSecond: 21,
				.inSeam: 50,
			]
		case .publicMock: [
				.drawn: 110,
				.valueFirst: 52,
				.wrapperFirst: 58,
				.sendableWrapper: 16,
				.screenReceivesOnlyIfAvailable: 26,
				.screenBuildsPanel: 38,
				.firstThroughInstantiator: 47,
				.topOpensSecond: 50,
			]
		}
	}
}

/// A shape of the twins draw, read from a graph's source.
enum TwinShape: String, CaseIterable {
	/// Every graph that draws the tree.
	case drawn
	/// `TwinFirst` declares the model by value, so the value is first on the path to the cycle.
	case valueFirst
	/// `TwinFirst` declares the model lazily, so the wrapper is first on the path to the cycle.
	case wrapperFirst
	/// The lazy twin is a `SendableLazilyInstantiated`, and the cycle closes through a `SendableInstantiator`.
	case sendableWrapper
	/// `TwinScreen` receives the model only if available.
	case screenReceivesOnlyIfAvailable
	/// `TwinScreen` builds `TwinPanel`, which receives the model too.
	case screenBuildsPanel
	/// The tree's top builds `TwinFirst` through an instantiator.
	case firstThroughInstantiator
	/// The tree's top opens `TwinSecond` too.
	case topOpensSecond
	/// `TwinSeam`, a seam, holds the tree.
	case inSeam

	static func shapes(of fixture: GraphFuzzerFixture) -> Set<TwinShape> {
		let prefix = GraphFuzzerFixture.typeNamePrefix(forSeed: fixture.seed)
		var shapes = Set<TwinShape>()
		var currentTypeName = ""
		for line in fixture.swiftFileContent.flatMap(GraphFuzzerSourceLine.lines(of:)) {
			switch line {
			case let .typeDeclaration(name):
				currentTypeName = name
				if name == "\(prefix)TwinRoot" || name == "\(prefix)TwinHome" {
					shapes.insert(.drawn)
				} else if name == "\(prefix)TwinSeam" {
					shapes.insert(.inSeam)
				}
			case let .property(attribute, label, type):
				switch currentTypeName {
				case "\(prefix)TwinFirst" where label == "twinModel":
					shapes.insert(type.contains("LazilyInstantiated<") ? .wrapperFirst : .valueFirst)
					if type.hasPrefix("SendableLazilyInstantiated<") {
						shapes.insert(.sendableWrapper)
					}
				case "\(prefix)TwinSecond" where label == "twinModel":
					if type.hasPrefix("SendableLazilyInstantiated<") {
						shapes.insert(.sendableWrapper)
					}
				case "\(prefix)TwinScreen":
					if attribute.contains("onlyIfAvailable") {
						shapes.insert(.screenReceivesOnlyIfAvailable)
					} else if label == "twinPanel" {
						shapes.insert(.screenBuildsPanel)
					}
				case "\(prefix)TwinRoot", "\(prefix)TwinSeam", "\(prefix)TwinHome":
					if label == "twinFirstBuilder" {
						shapes.insert(.firstThroughInstantiator)
					} else if label == "twinSecondBuilder" {
						shapes.insert(.topOpensSecond)
					}
				default:
					break
				}
			case .instantiableAttribute, .instantiateMethod, .other:
				break
			}
		}
		return shapes
	}
}
