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

/// The one-function-per-class oracle of shared mock bodies (`GraphFuzzerMockSharedBodies`), judged on the mocks
/// `SafeDIToolMockSharedBodyTests` expects and on hand-made copies of them, and the base corpus's draw of a type one
/// mock builds at three places (`addingMockSharedPlaceShapes`).
struct SafeDIToolGraphFuzzerMockSharedBodyTests {
	@Test
	func baseCorpus_drawsEachVariantOfMockSharedPlaces_inPinnedNumberOfGraphs() {
		// Each variant lands in exactly the pinned number of the corpus's graphs, read from their source, and in at least ten:
		// the draw is deterministic, so a change in a variant's share is a reviewed diff.
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
	func functionsRepeatingAClass_isEmpty_whenEachClassHasOneFunction() {
		// `__safeDI_a` and `__safeDI_b` have bodies alike once names are mapped, but return other types, so each is a class of its own.
		#expect(GraphFuzzerMockSharedBodies.functionsRepeatingAClass(in: ["Screen+SafeDIMock.swift": Self.sharedMock]).isEmpty)
		#expect(GraphFuzzerMockSharedBodies.sharedBodyCount(in: ["Screen+SafeDIMock.swift": Self.sharedMock]) == 1)
	}

	@Test
	func functionsRepeatingAClass_reportsCopy_whenPlaceCallsCopyOfSharedFunctionUnderNextName() {
		// The hand mutation of the shared-body generator the oracle must catch: `B`’s place gets a copy of `__safeDI_leaf`, named apart, which it calls instead of the function itself.
		let mutated = Self.sharedMock.replacingOccurrences(
			of: """
			        func __safeDI_b(safeDIOverrides __safeDI_overrides: B.SafeDIMockConfiguration) -> B {
			            let leafBuilder = Instantiator<Leaf> {
			                __safeDI_leaf(safeDIOverrides: __safeDI_overrides.leafBuilder)
			""",
			with: """
			        func __safeDI_leaf_(safeDIOverrides __safeDI_overrides: Leaf.SafeDIMockConfiguration) -> Leaf {
			            let model = if let safeDIBuilder = __safeDI_overrides.model { safeDIBuilder(service) } else { Model(service: service) }
			            return if let safeDIBuilder = __safeDI_overrides.safeDIBuilder { safeDIBuilder(service, model) } else { Leaf(service: service, model: model) }
			        }
			        func __safeDI_b(safeDIOverrides __safeDI_overrides: B.SafeDIMockConfiguration) -> B {
			            let leafBuilder = Instantiator<Leaf> {
			                __safeDI_leaf_(safeDIOverrides: __safeDI_overrides.leafBuilder)
			""",
		)
		#expect(mutated != Self.sharedMock)

		#expect(GraphFuzzerMockSharedBodies.functionsRepeatingAClass(in: ["Screen+SafeDIMock.swift": mutated]) == [
			"`__safeDI_leaf_` in `Screen.mock()` in `Screen+SafeDIMock.swift` builds the class of `__safeDI_leaf` again.",
		])
	}

	@Test
	func functionsRepeatingAClass_isEmpty_whenErasedAndPlainPlacesReadOneConfigurationType() {
		// The class carries the return type, so the erased place’s function and the plain one’s are two classes, though both take `Leaf.SafeDIMockConfiguration`.
		let mock = """
		extension Screen {
		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_leafBuilder(service: Service, safeDIOverrides __safeDI_overrides: Leaf.SafeDIMockConfiguration) -> Leaf {
		            let model = if let safeDIBuilder = __safeDI_overrides.model { safeDIBuilder(service) } else { Model(service: service) }
		            return if let safeDIBuilder = __safeDI_overrides.safeDIBuilder { safeDIBuilder(service, model) } else { Leaf(service: service, model: model) }
		        }
		        func __safeDI_leafBuilder_(service: Service, safeDIOverrides __safeDI_overrides: Leaf.SafeDIMockConfiguration) -> AnyLeaf {
		            let model = if let safeDIBuilder = __safeDI_overrides.model { safeDIBuilder(service) } else { Model(service: service) }
		            return if let safeDIBuilder = __safeDI_overrides.safeDIBuilder { AnyLeaf(safeDIBuilder(service, model)) } else { AnyLeaf(Leaf(service: service, model: model)) }
		        }
		        return Screen()
		    }
		}
		"""

		#expect(GraphFuzzerMockSharedBodies.functionsRepeatingAClass(in: ["Screen+SafeDIMock.swift": mock]).isEmpty)
	}

	@Test
	func sharedBodyCount_isZero_whenMockKeepsTodaysBody() {
		// A root one of whose places cannot be shared keeps today’s body, whose builder functions take no configuration parameter: the oracle judges nothing there.
		let mock = """
		extension Screen {
		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_leaf() -> Leaf {
		            Leaf()
		        }
		        let leaf: Leaf = __safeDI_leaf()
		        func __safeDI_other() -> Leaf {
		            Leaf()
		        }
		        let other: Leaf = __safeDI_other()
		        return Screen(leaf: leaf, other: other)
		    }
		}
		"""

		#expect(GraphFuzzerMockSharedBodies.sharedBodyCount(in: ["Screen+SafeDIMock.swift": mock]) == 0)
		#expect(GraphFuzzerMockSharedBodies.functionsRepeatingAClass(in: ["Screen+SafeDIMock.swift": mock]).isEmpty)
	}

	// MARK: Private

	/// A variant of the draw, read from a graph's source.
	private enum Shape: String, CaseIterable {
		/// Every graph that draws the tree.
		case drawn
		/// Every place reads the `mockSharedService` `MockSharedScreen` instantiates.
		case equalReads
		/// `MockSharedScreen` receives `mockSharedService` and `MockSharedPlaceB` instantiates one of its own.
		case promotedAndParentBuiltReads
		/// `MockSharedPlaceB` receives `mockSharedService` only if available, as `MockSharedLeaf` does.
		case optionalDeclarationRead
		/// `MockSharedPlaceC` holds its leaf erased to `MockSharedAnyLeaf`.
		case erasedPlace
	}

	private static let drawnShapeCounts: [Shape: Int] = [
		.drawn: 214,
		.equalReads: 54,
		.promotedAndParentBuiltReads: 59,
		.optionalDeclarationRead: 43,
		.erasedPlace: 58,
	]

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
		guard declaredTypeNames.contains("\(prefix)MockSharedScreen") else { return [] }
		var shapes: Set<Shape> = [.drawn]
		if propertyLines.contains("\(prefix)MockSharedScreen: @Received let mockSharedService: \(prefix)MockSharedService") {
			shapes.insert(.promotedAndParentBuiltReads)
		} else if propertyLines.contains("\(prefix)MockSharedPlaceB: @Received(onlyIfAvailable: true) let mockSharedService: \(prefix)MockSharedService?") {
			shapes.insert(.optionalDeclarationRead)
		} else if propertyLines.contains(where: { $0.hasPrefix("\(prefix)MockSharedPlaceC: ") && $0.contains("erasedToConcreteExistential: true") }) {
			shapes.insert(.erasedPlace)
		} else {
			shapes.insert(.equalReads)
		}
		return shapes
	}

	/// The mock `SafeDIToolMockSharedBodyTests`' first cell expects: `Leaf` built at three places, in one function.
	private static let sharedMock = """
	extension Screen {
	    static func mock(
	        safeDIOverrides: SafeDIOverrides = .init()
	    ) -> Screen {
	        let service = if let safeDIBuilder = safeDIOverrides.service { safeDIBuilder() } else { Service() }
	        func __safeDI_leaf(safeDIOverrides __safeDI_overrides: Leaf.SafeDIMockConfiguration) -> Leaf {
	            let model = if let safeDIBuilder = __safeDI_overrides.model { safeDIBuilder(service) } else { Model(service: service) }
	            return if let safeDIBuilder = __safeDI_overrides.safeDIBuilder { safeDIBuilder(service, model) } else { Leaf(service: service, model: model) }
	        }
	        let leaf: Leaf = __safeDI_leaf(safeDIOverrides: safeDIOverrides.leaf)
	        func __safeDI_a(safeDIOverrides __safeDI_overrides: A.SafeDIMockConfiguration) -> A {
	            let leafBuilder = Instantiator<Leaf> {
	                __safeDI_leaf(safeDIOverrides: __safeDI_overrides.leafBuilder)
	            }
	            return if let safeDIBuilder = __safeDI_overrides.safeDIBuilder { safeDIBuilder(leafBuilder) } else { A(leafBuilder: leafBuilder) }
	        }
	        let a: A = __safeDI_a(safeDIOverrides: safeDIOverrides.a)
	        func __safeDI_b(safeDIOverrides __safeDI_overrides: B.SafeDIMockConfiguration) -> B {
	            let leafBuilder = Instantiator<Leaf> {
	                __safeDI_leaf(safeDIOverrides: __safeDI_overrides.leafBuilder)
	            }
	            return if let safeDIBuilder = __safeDI_overrides.safeDIBuilder { safeDIBuilder(leafBuilder) } else { B(leafBuilder: leafBuilder) }
	        }
	        let b: B = __safeDI_b(safeDIOverrides: safeDIOverrides.b)
	        return Screen(service: service, leaf: leaf, a: a, b: b)
	    }
	}
	"""
}
