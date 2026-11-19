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

/// The base corpus's draw of a type a mock builds twice with differing pins (`addingTypeBuiltTwiceWithDifferingPins`),
/// and the value oracle's pair that judges its mocks (`GraphFuzzerValueOraclePlan.pinnedPlacePair`).
struct SafeDIToolGraphFuzzerDifferingPinsTests {
	@Test
	func baseCorpus_drawsEachShapeOfTypeBuiltTwiceWithDifferingPins_inPinnedNumberOfGraphs() {
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
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func valueOraclePlan_comparesPinScreensMockWithProductionsBuild_forSeed519() {
		// Seed 519 draws the shape plainly: `PinSource` requires the pinning form above its `PinLeaf`, and `PinOther`, a
		// second dependency `PinScreen` receives, builds `PinReader` beside the other `PinLeaf`. A mock that judged
		// `PinLeaf` by its type, rather than by its place, handed both `PinLeaf`s its `PinToken`, which this pair reports.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: 519)

		#expect(Self.propertyDeclarations(of: "S519_PinScreen", in: fixture) == [
			"@Received let pinSource: S519_PinSource",
			"@Received let pinOther: S519_PinOther",
		])
		#expect(Self.propertyDeclarations(of: "S519_PinSource", in: fixture) == [
			"@Received let pinToken: Instantiator<S519_PinToken>",
			"@Instantiated let pinLeaf: S519_PinLeaf",
		])
		#expect(Self.propertyDeclarations(of: "S519_PinOther", in: fixture) == [
			"@Instantiated let pinReader: S519_PinReader",
			"@Instantiated let pinLeaf: S519_PinLeaf",
		])
		#expect(Self.propertyDeclarations(of: "S519_PinLeaf", in: fixture) == [
			"@Received(onlyIfAvailable: true) let pinToken: S519_PinToken?",
		])
		#expect(Self.propertyDeclarations(of: "S519_PinHost", in: fixture) == [
			"@Instantiated let pinToken: Instantiator<S519_PinToken>",
			"@Instantiated let pinSource: S519_PinSource",
			"@Instantiated let pinMiddle: S519_PinMiddle",
		])
		#expect(Self.propertyDeclarations(of: "S519_PinMiddle", in: fixture) == [
			"@Instantiated let pinToken: S519_PinToken",
			"@Instantiated let pinOther: S519_PinOther",
			"@Instantiated let pinScreen: S519_PinScreen",
		])
		let plan = GraphFuzzerValueOraclePlan(fixture: fixture, generatedFiles: [:])
		#expect(plan.pinnedPlacePair == DifferentialValueProbePair(
			name: "S519_PinScreen.mock() against production",
			featureExpression: "S519_PinScreen.mock()",
			knownRightExpression: "S519_ZPinRoot().pinHost.pinMiddle.pinScreen",
		))
		#expect(plan.valueOracleFixture(storingEveryParameter: false).swiftFileContent.last == """
		@Instantiable(isRoot: true)
		public final class S519_ZPinRoot: Instantiable {
			public init(pinHost: S519_PinHost) {
				self.pinHost = pinHost
			}

			@Instantiated let pinHost: S519_PinHost
		}

		""")
	}

	@Test
	func corpusValueOracleCounts_compareTenPinnedPlacePairs_whenPinsAreRead() {
		// The pair stands in for unit tests of the draw's shapes only while the value oracle compares it in at least ten
		// graphs the tool accepts, which the corpus runs pin exactly.
		#expect(SafeDIToolGraphFuzzerTests.corpusValueOracleCounts.pinnedPlacePairCount >= SafeDIToolGraphFuzzerTests.gatingDrawJudgedGraphFloor)
	}

	// MARK: Private

	/// A shape of the draw, read from a graph's source.
	private enum Shape: String, CaseIterable {
		/// Every graph that draws the tree.
		case drawn
		/// `PinHolder`, beneath `PinSource`, requires the pinning form, rather than `PinSource` itself.
		case pinnedByHolder
		/// `PinLeaf` declares an `onlyIfAvailable` alias of `pinToken`.
		case leafAliasesLabel
		/// `PinMaker`'s instantiator builds the pinned `PinLeaf`.
		case pinnedPlaceThroughInstantiator
		/// The unpinned `PinLeaf` is in `PinOther`'s tree, a second promoted dependency, rather than `PinScreen`'s own.
		case unpinnedInAnotherPromotedTree
		/// The pinning form is a `SendableInstantiator`.
		case sendablePinningForm
	}

	private static let drawnShapeCounts: [Shape: Int] = [
		.drawn: 199,
		.pinnedByHolder: 73,
		.leafAliasesLabel: 61,
		.pinnedPlaceThroughInstantiator: 65,
		.unpinnedInAnotherPromotedTree: 85,
		.sendablePinningForm: 26,
	]

	/// The properties the type named `typeName` declares in `fixture`, each as `<attribute> let <label>: <type>`.
	private static func propertyDeclarations(of typeName: String, in fixture: GraphFuzzerFixture) -> [String] {
		var currentTypeName = ""
		return fixture.swiftFileContent.flatMap(GraphFuzzerSourceLine.lines(of:)).compactMap { line in
			switch line {
			case let .typeDeclaration(name):
				currentTypeName = name
				return nil
			case let .property(attribute, label, type):
				return currentTypeName == typeName ? "\(attribute) let \(label): \(type)" : nil
			case .instantiableAttribute, .instantiateMethod, .other:
				return nil
			}
		}
	}

	private static func shapes(of fixture: GraphFuzzerFixture) -> Set<Shape> {
		let prefix = fixture.typeNamePrefix
		var declaredTypeNames = Set<String>()
		var propertyLines = Set<String>()
		var currentTypeName = ""
		for line in fixture.swiftFileContent.flatMap(GraphFuzzerSourceLine.lines(of:)) {
			switch line {
			case let .typeDeclaration(name):
				currentTypeName = name
				declaredTypeNames.insert(name)
			case let .property(attribute, label, type):
				propertyLines.insert("\(currentTypeName): \(attribute) let \(label): \(type)")
			case .instantiableAttribute, .instantiateMethod, .other:
				break
			}
		}
		guard declaredTypeNames.contains("\(prefix)PinScreen") else { return [] }
		var shapes: Set<Shape> = [.drawn]
		if declaredTypeNames.contains("\(prefix)PinHolder") {
			shapes.insert(.pinnedByHolder)
		}
		if propertyLines.contains(where: { $0.hasPrefix("\(prefix)PinLeaf: ") && $0.contains("let pinTokenAlias: ") }) {
			shapes.insert(.leafAliasesLabel)
		}
		if declaredTypeNames.contains("\(prefix)PinMaker") {
			shapes.insert(.pinnedPlaceThroughInstantiator)
		}
		if declaredTypeNames.contains("\(prefix)PinOther") {
			shapes.insert(.unpinnedInAnotherPromotedTree)
		}
		if propertyLines.contains("\(prefix)PinHost: @Instantiated let pinToken: SendableInstantiator<\(prefix)PinToken>") {
			shapes.insert(.sendablePinningForm)
		}
		return shapes
	}
}
