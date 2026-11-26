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

/// The base corpus's draw of a dependency instantiated only if available
/// (`addingDependencyInstantiatedOnlyIfAvailable`).
struct SafeDIToolGraphFuzzerInstantiatedOnlyIfAvailableTests {
	@Test
	func baseCorpus_drawsEachShapeOfDependencyInstantiatedOnlyIfAvailable_inPinnedNumberOfGraphs() {
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

	// MARK: Private

	private enum Shape: String, CaseIterable {
		/// The graph holds `IfAvailableScreen`'s tree.
		case drawn
		/// The screen declares the token before the leaf whose tree receives it.
		case tokenDeclaredFirst
		/// The screen declares the leaf before the token its tree receives.
		case leafDeclaredFirst
		/// The leaf requires the optional form.
		case leafRequiresToken
		/// An `Instantiator` builds the leaf.
		case leafBuiltByInstantiator
		/// The root builds a second leaf, outside the screen's tree.
		case leafBuiltOutsideScreen
		/// The screen's mock is generated.
		case screenGeneratesMock
		/// No declaration fulfills the token, so the property is `nil`.
		case tokenUnfulfilled
		/// No declaration fulfills the token and the screen's mock is generated.
		case tokenUnfulfilledUnderGeneratedMock
	}

	private static let drawnShapeCounts: [Shape: Int] = [
		.drawn: 819,
		.tokenDeclaredFirst: 427,
		.leafDeclaredFirst: 392,
		.leafRequiresToken: 314,
		.leafBuiltByInstantiator: 299,
		.leafBuiltOutsideScreen: 195,
		.screenGeneratesMock: 320,
		.tokenUnfulfilled: 318,
		.tokenUnfulfilledUnderGeneratedMock: 124,
	]

	/// The shapes of the draw `fixture` holds, read from its source.
	private static func shapes(of fixture: GraphFuzzerFixture) -> Set<Shape> {
		let prefix = fixture.typeNamePrefix
		var currentTypeName = ""
		var mockedTypeNames = Set<String>()
		var instantiableTypeNames = Set<String>()
		var pendingAttribute: String?
		var propertyLinesByTypeName = [String: [String]]()
		for line in fixture.swiftFileContent.flatMap(GraphFuzzerSourceLine.lines(of:)) {
			switch line {
			case let .instantiableAttribute(attribute):
				pendingAttribute = attribute
			case let .typeDeclaration(name):
				currentTypeName = name
				if let pendingAttribute {
					instantiableTypeNames.insert(name)
					if pendingAttribute.contains("generateMock: true") {
						mockedTypeNames.insert(name)
					}
				}
				pendingAttribute = nil
			case let .property(attribute, label, type):
				propertyLinesByTypeName[currentTypeName, default: []].append("\(attribute) let \(label): \(type)")
			case .instantiateMethod, .other:
				break
			}
		}
		let screenName = "\(prefix)IfAvailableScreen"
		guard let screenLines = propertyLinesByTypeName[screenName] else { return [] }
		var shapes: Set<Shape> = [.drawn]
		shapes.insert(screenLines.first?.hasPrefix("@Instantiated(onlyIfAvailable: true)") == true ? .tokenDeclaredFirst : .leafDeclaredFirst)
		if propertyLinesByTypeName["\(prefix)IfAvailableLeaf"]?.contains(where: { $0.hasPrefix("@Received let ") }) == true {
			shapes.insert(.leafRequiresToken)
		}
		if screenLines.contains(where: { $0.contains("let ifAvailableLeafBuilder: ") }) {
			shapes.insert(.leafBuiltByInstantiator)
		}
		if propertyLinesByTypeName["\(prefix)IfAvailableRoot"]?.contains(where: { $0.contains("let ifAvailableOuterLeaf: ") }) == true {
			shapes.insert(.leafBuiltOutsideScreen)
		}
		if mockedTypeNames.contains(screenName) {
			shapes.insert(.screenGeneratesMock)
		}
		if !instantiableTypeNames.contains("\(prefix)IfAvailableToken") {
			shapes.insert(.tokenUnfulfilled)
			if mockedTypeNames.contains(screenName) {
				shapes.insert(.tokenUnfulfilledUnderGeneratedMock)
			}
		}
		return shapes
	}
}
