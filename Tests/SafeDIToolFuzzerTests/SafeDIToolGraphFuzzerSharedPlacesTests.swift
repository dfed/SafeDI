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

/// The base corpus's draw of one type a mock builds at several places of its tree (`addingTypeBuiltAtSeveralPlacesOfOneMock`).
struct SafeDIToolGraphFuzzerSharedPlacesTests {
	@Test
	func baseCorpus_drawsEachShapeOfTypeBuiltAtSeveralPlaces_inPinnedNumberOfGraphs() {
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
	func otherCorpora_drawNoTypeBuiltAtSeveralPlaces() {
		for features: Set<GraphFuzzerGeneratorFeature> in [[.generateDependencyTree], [.generateMockPublic]] {
			for seed in UInt64(0)..<200 {
				#expect(Self.shapes(of: GraphFuzzerGenerator.fixture(forSeed: seed, features: features)).isEmpty, "seed \(seed) of \(features)")
			}
		}
	}

	// MARK: Helpers

	/// What a graph of the draw shows, read from its source.
	enum Shape: String, CaseIterable {
		/// `ShareHost`'s tree: the draw landed.
		case drawn
		/// A parent holds `ShareLeaf` by value.
		case placeByValue
		/// A parent holds `ShareLeaf` through an instantiator.
		case placeThroughInstantiator
		/// A parent holds `ShareLeaf` through an erased instantiator.
		case placeThroughErasedInstantiator
		/// A parent holds `ShareLeaf` through a lazily instantiated wrapper.
		case placeThroughLazilyInstantiated
		/// A parent holds `ShareForm`'s instantiator, which forwards `shareValue` beside `ShareLeaf`.
		case placeBesideForwardedValue
		/// A parent holds `ShareLeaf` three levels beneath the mock's root.
		case placeAtDepthThree
		/// `ShareLeaf` receives a value only if available.
		case leafReceivesOnlyIfAvailable
		/// `ShareLeaf` builds a child of its own, so its override is a configuration.
		case leafBuildsChild
	}

	static let drawnShapeCounts: [Shape: Int] = [
		.drawn: 574,
		.placeByValue: 170,
		.placeThroughInstantiator: 187,
		.placeThroughErasedInstantiator: 164,
		.placeThroughLazilyInstantiated: 184,
		.placeBesideForwardedValue: 176,
		.placeAtDepthThree: 182,
		.leafReceivesOnlyIfAvailable: 383,
		.leafBuildsChild: 358,
	]

	static func shapes(of fixture: GraphFuzzerFixture) -> Set<Shape> {
		let prefix = fixture.typeNamePrefix
		let source = fixture.swiftFileContent.joined(separator: "\n")
		guard source.contains("class \(prefix)ShareHost:") else { return [] }
		var shapes: Set<Shape> = [.drawn]
		let parentSources = fixture.swiftFileContent.filter { $0.contains("class \(prefix)ShareParent") }
		if parentSources.contains(where: { $0.contains("@Instantiated let shareLeaf: \(prefix)ShareLeaf") }) {
			shapes.insert(.placeByValue)
		}
		if source.contains("let shareLeafBuilder:") {
			shapes.insert(.placeThroughInstantiator)
		}
		if source.contains("let shareLeafErased:") {
			shapes.insert(.placeThroughErasedInstantiator)
		}
		if source.contains("let shareLeafLazy:") {
			shapes.insert(.placeThroughLazilyInstantiated)
		}
		if source.contains("let shareFormBuilder:") {
			shapes.insert(.placeBesideForwardedValue)
		}
		if source.contains("let shareMiddle:") {
			shapes.insert(.placeAtDepthThree)
		}
		if source.contains("@Received(onlyIfAvailable: true) let shareValue:") || source.contains("@Received(onlyIfAvailable: true) let shareNote:") {
			shapes.insert(.leafReceivesOnlyIfAvailable)
		}
		if source.contains("@Instantiated let sharePart:") {
			shapes.insert(.leafBuildsChild)
		}
		return shapes
	}
}
