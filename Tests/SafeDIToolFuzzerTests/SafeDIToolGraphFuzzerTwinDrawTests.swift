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
/// public mock form in the public mock corpus. The seam and public mock corpora count each shape as a draw feature, drawn
/// and accepted (`seamCorpusDrawFeatureCounts`, `seamCorpusAcceptedDrawFeatureCounts` and their public mock twins); the
/// base corpus's drawn counts are pinned here.
struct SafeDIToolGraphFuzzerTwinDrawTests {
	@Test
	func baseCorpus_drawsEachShapeOfTwinsOverSharedScreen_inPinnedNumberOfGraphs() {
		// Each shape lands in exactly the pinned number of the base corpus's graphs, read from their source: the draw is
		// deterministic, so a change in a shape's share is a reviewed diff.
		var counts = [TwinShape: Int]()
		for seed in 0..<UInt64(SafeDIToolGraphFuzzerTests.corpusSeedCount) {
			for shape in TwinShape.shapes(of: GraphFuzzerGenerator.fixture(forSeed: seed)) {
				counts[shape, default: 0] += 1
			}
		}
		#expect(counts == Self.baseCorpusDrawnShapeCounts)
	}

	@Test(arguments: TwinSeed.all)
	func toolRuns_acceptTwinsOverSharedScreen_forSeedsCoveringEveryShape(seed: TwinSeed) async throws {
		// These seeds together draw every shape of their corpus, and the tool accepts each: no error names the draw's
		// types. Where the root holds the twins, the plan sees them (`PlanBodiesObservation`'s twin values), so
		// `TwinIdentityChecks`, which every graph runs, judges each. The rest of the corpus's graphs are the long run's.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: seed.seed, features: seed.corpus.features)
		#expect(TwinShape.shapes(of: fixture) == seed.shapes)
		let (stream, continuation) = AsyncStream.makeStream(of: String.self)
		let outcome: GraphFuzzerToolOutcome = if seed.corpus == .base {
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
			Issue.record("\(seed.testDescription) is rejected: \(diagnostics)")
		case .accepted:
			#expect(seed.corpus != .base || rootsHoldingTwins >= 1, "\(seed.testDescription): the plan sees no twin in TwinRoot")
		}
	}

	@Test
	func twinSeeds_drawEveryShapeOfTheirCorpus() {
		for corpus in TwinCorpus.allCases {
			let shapes = TwinSeed.all.filter { $0.corpus == corpus }.reduce(into: Set<TwinShape>()) { $0.formUnion($1.shapes) }
			#expect(shapes == corpus.shapes, "\(corpus)")
		}
	}

	private static let baseCorpusDrawnShapeCounts: [TwinShape: Int] = [
		.drawn: 187,
		.valueFirst: 93,
		.wrapperFirst: 94,
		.sendableWrapper: 48,
		.screenReceivesOnlyIfAvailable: 67,
		.screenBuildsPanel: 76,
		.firstThroughInstantiator: 91,
		.topOpensSecond: 78,
		.themeInSameForm: 81,
		.themeInMixedForms: 36,
		.themeInMixedFormsInsideSendableBuilder: 3,
	]
}

/// A corpus that draws twins over a shared screen.
enum TwinCorpus: String, CaseIterable {
	case base
	case seam
	case publicMock

	var features: Set<GraphFuzzerGeneratorFeature> {
		switch self {
		case .base: []
		case .seam: [.generateDependencyTree]
		case .publicMock: [.generateMockPublic]
		}
	}

	/// The shapes the corpus draws.
	var shapes: Set<TwinShape> {
		switch self {
		case .base: Set(TwinShape.allCases).subtracting([.inSeam])
		case .seam: Set(TwinShape.allCases)
		case .publicMock: Set(TwinShape.allCases).subtracting([.inSeam, .themeInSameForm, .themeInMixedForms, .themeInMixedFormsInsideSendableBuilder])
		}
	}
}

/// A seed whose graph the tool accepts, and the twin shapes it draws.
struct TwinSeed: CustomTestStringConvertible, Sendable {
	let corpus: TwinCorpus
	let seed: UInt64
	let shapes: Set<TwinShape>

	var testDescription: String {
		"\(corpus.rawValue) seed \(seed)"
	}

	static let all: [TwinSeed] = [
		TwinSeed(corpus: .base, seed: 2_449, shapes: [.drawn, .firstThroughInstantiator, .screenBuildsPanel, .screenReceivesOnlyIfAvailable, .themeInSameForm, .topOpensSecond, .wrapperFirst]),
		TwinSeed(corpus: .base, seed: 3_698, shapes: [.drawn, .screenBuildsPanel, .sendableWrapper, .themeInMixedForms, .themeInMixedFormsInsideSendableBuilder, .valueFirst]),
		TwinSeed(corpus: .seam, seed: 62, shapes: [.drawn, .inSeam, .themeInSameForm, .wrapperFirst]),
		TwinSeed(corpus: .seam, seed: 98, shapes: [.drawn, .firstThroughInstantiator, .inSeam, .screenBuildsPanel, .screenReceivesOnlyIfAvailable, .wrapperFirst]),
		TwinSeed(corpus: .seam, seed: 897, shapes: [.drawn, .firstThroughInstantiator, .inSeam, .sendableWrapper, .themeInMixedForms, .themeInMixedFormsInsideSendableBuilder, .topOpensSecond, .valueFirst]),
		TwinSeed(corpus: .publicMock, seed: 60, shapes: [.drawn, .screenReceivesOnlyIfAvailable, .wrapperFirst]),
		TwinSeed(corpus: .publicMock, seed: 330, shapes: [.drawn, .firstThroughInstantiator, .screenBuildsPanel, .sendableWrapper, .topOpensSecond, .valueFirst]),
	]
}
