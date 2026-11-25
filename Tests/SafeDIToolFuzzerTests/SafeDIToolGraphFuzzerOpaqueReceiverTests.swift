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
import Testing
@testable import SafeDIToolTestSupport

/// The base corpus's draw of an opaque receiver of an `@Instantiable` extension (`addingOpaqueReceiverOfExtension`).
struct SafeDIToolGraphFuzzerOpaqueReceiverTests {
	@Test
	func baseCorpus_drawsEachShapeOfOpaqueReceiver_inPinnedNumberOfGraphs() {
		// Each shape lands in exactly the pinned number of the corpus's graphs, read from their source, and in at least ten:
		// the draw is deterministic, so a change in a shape's share is a reviewed diff.
		var counts = [Shape: Int]()
		for seed in 0..<UInt64(SafeDIToolGraphFuzzerTests.corpusSeedCount) {
			for shape in Self.shapes(of: GraphFuzzerGenerator.fixture(forSeed: seed)) {
				counts[shape, default: 0] += 1
			}
		}
		for shape in Shape.allCases {
			#expect(counts[shape, default: 0] == Self.drawnShapeCounts[shape], "\(shape.rawValue) drawn in \(counts[shape, default: 0]) graphs")
			#expect(counts[shape, default: 0] >= SafeDIToolGraphFuzzerTests.gatingDrawJudgedGraphFloor, "\(shape.rawValue) drawn in fewer than ten graphs")
		}
	}

	@Test
	func otherCorpora_drawNoOpaqueReceiver() {
		for features: Set<GraphFuzzerGeneratorFeature> in [[.generateDependencyTree], [.generateMockPublic]] {
			for seed in UInt64(0)..<200 {
				#expect(Self.shapes(of: GraphFuzzerGenerator.fixture(forSeed: seed, features: features)).isEmpty, "seed \(seed) of \(features)")
			}
		}
	}

	// MARK: Helpers

	/// What a graph of the draw shows, read from its source.
	enum Shape: String, CaseIterable {
		/// `OpaqueConsumer`'s tree: the draw landed.
		case drawn
		/// The opaque type's protocol is declared at top level.
		case topLevelProtocol
		/// The protocol is nested in `OpaqueConsumer`, and `instantiate(…)` spells it qualified.
		case nestedProtocolSpelledQualified
		/// The protocol is nested in `OpaqueConsumer`, and `instantiate(…)` spells it unqualified.
		case nestedProtocolSpelledUnqualified
		/// `OpaqueConsumer` generates its own mock, which promotes the opaque receive.
		case consumerMocked
		/// `OpaqueHost`'s mock builds `OpaqueConsumer` by value.
		case builtByMockedHost
		/// `OpaqueHost`'s mock builds `OpaqueConsumer` through an instantiator.
		case builtThroughInstantiatorByMockedHost
	}

	static let drawnShapeCounts: [Shape: Int] = [
		.drawn: 526,
		.topLevelProtocol: 263,
		.nestedProtocolSpelledQualified: 123,
		.nestedProtocolSpelledUnqualified: 140,
		.consumerMocked: 253,
		.builtByMockedHost: 293,
		.builtThroughInstantiatorByMockedHost: 134,
	]

	static func shapes(of fixture: GraphFuzzerFixture) -> Set<Shape> {
		let prefix = fixture.typeNamePrefix
		let source = fixture.swiftFileContent.joined(separator: "\n")
		guard source.contains("extension \(prefix)OpaqueConsumer: Instantiable") else { return [] }
		var shapes: Set<Shape> = [.drawn]
		if source.contains("opaqueService: some \(prefix)OpaqueApi)") {
			shapes.insert(.topLevelProtocol)
		}
		if source.contains("opaqueService: some \(prefix)OpaqueConsumer.Api)") {
			shapes.insert(.nestedProtocolSpelledQualified)
		}
		if source.contains("opaqueService: some Api)") {
			shapes.insert(.nestedProtocolSpelledUnqualified)
		}
		if source.contains("@Instantiable(generateMock: true)\nextension \(prefix)OpaqueConsumer") {
			shapes.insert(.consumerMocked)
		}
		if source.contains("@Instantiated let opaqueConsumer: \(prefix)OpaqueConsumer") {
			shapes.insert(.builtByMockedHost)
		}
		if source.contains("let opaqueConsumerBuilder:") {
			shapes.insert(.builtThroughInstantiatorByMockedHost)
		}
		return shapes
	}
}
