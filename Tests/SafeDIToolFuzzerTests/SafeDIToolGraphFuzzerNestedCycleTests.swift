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

/// The base corpus's draw of a type built again through a second lazy cycle (`addingTypeBuiltAgainThroughSecondLazyCycle`),
/// and the value oracle's pair that judges its production build (`GraphFuzzerValueOraclePlan.nestedCyclePair`).
struct SafeDIToolGraphFuzzerNestedCycleTests {
	@Test
	func baseCorpus_drawsEachShapeOfTypeBuiltAgainThroughSecondLazyCycle_inPinnedNumberOfGraphs() {
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

	@Test(arguments: [UInt64(222), 1501])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func toolRuns_rejectFillWithDeclarationBoundOnCycleReentry_whenNoTypeOfNestedCyclesReceivesLabel(seed: UInt64) async throws {
		// The seam corpus's `addingNestedCycleHoleShapes`, unremedied: `NestHoleRedeclarer` declares `nestHoleTag` again
		// inside the second cycle, no type of the cycles receives it, so no builder function takes it, and `NestHoleLive`,
		// filling a place on `NestHoleOuter`'s level from the roots' module, reads it. Inline, and in the visible build,
		// which fills the place in the seam's module, the `NestHoleOuter` built beneath `NestHoleRedeclarer` reads that
		// type's tag; the seam hands the fill the same values at every level of a cycle, so the tool rejects the read and
		// offers the receive on `NestHoleOuter`. With the declarations of a cycle nested between left out of
		// `SeamBuilderParameters.declarationsBetween`, the tool accepts both seeds and the fill beneath `NestHoleRedeclarer`
		// reads `NestHoleHome`'s tag, which the comparison with the visible build reports
		// (`holeBuildsOtherValuesThanVisibleBuild`). Seed 222's place is on `NestHoleOuter`,
		// seed 1501's on `NestHoleScreen`.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateDependencyTree])
		let drawFeatures = GraphFuzzerFeature.seamDrawFeatures(of: fixture)
		#expect(drawFeatures.contains(.nestedCycleHoleLabelNoFunctionTakes))
		#expect(drawFeatures.contains(.nestedCycleHolePlaceOnScreen) == (seed == 1501))
		let runs = try await GraphFuzzerOracle.toolRuns(of: fixture, renamings: [])
		let prefix = fixture.typeNamePrefix
		guard case let .rejected(diagnostics) = runs.firstOutcome else {
			Issue.record("Seed \(seed) is not rejected")
			return
		}
		let findings = diagnostics.split(separator: "\n").filter { $0.contains("`\(prefix)NestHoleLive` receives `nestHoleTag: ") }
		#expect(!findings.isEmpty && findings.allSatisfy {
			$0.contains("because a cycle inside `\(prefix)NestHoleInner`’s tree passes it (`\(prefix)NestHoleRedeclarer` declares `nestHoleTag: \(prefix)NestHoleTag`)")
				&& $0.contains("the same values at every level of that cycle")
				&& $0.contains("Declare `@Received let nestHoleTag: \(prefix)NestHoleTag` on `\(prefix)NestHoleOuter`, so each `\(prefix)NestHoleOuter` receives the `nestHoleTag` of its own level and hands it on")
		}, "Seed \(seed):\n\(diagnostics)")
		guard case .accepted? = runs.visibleOutcome else {
			Issue.record("Seed \(seed)’s visible build is not accepted")
			return
		}
	}

	@Test(arguments: [UInt64(132), 471])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func toolRuns_acceptBothBuildsWithVisibleBuildsValues_whenTypeBuiltAgainThroughSecondCycleReceivesLabelItsPlacesFillReads(seed: UInt64) async throws {
		// The remedy, as the draw applies it: `NestHoleOuter` receives `nestHoleTag`, so each level's builder function takes
		// it and the fill reads its own level's. Both builds accept the graph, and every oracle passes, the comparison of
		// the hole build's values with the visible build's and the inline build's included. Seed 132's place is on
		// `NestHoleOuter`, seed 471's on `NestHoleScreen`.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: seed, features: [.generateDependencyTree])
		let drawFeatures = GraphFuzzerFeature.seamDrawFeatures(of: fixture)
		#expect(drawFeatures.contains(.nestedCycleHoleLabelReceivedByTypeBuiltAgain))
		#expect(drawFeatures.contains(.nestedCycleHolePlaceOnScreen) == (seed == 471))
		let runs = try await GraphFuzzerOracle.toolRuns(of: fixture, renamings: [])
		for (build, outcome) in [("hole", Optional(runs.firstOutcome)), ("visible", runs.visibleOutcome)] {
			switch outcome {
			case .accepted?:
				break
			case let .rejected(diagnostics)?:
				Issue.record("Seed \(seed)’s \(build) build is rejected:\n\(diagnostics)")
			case nil:
				Issue.record("Seed \(seed) has no \(build) build")
			}
		}
		let results = try await GraphFuzzerOracle.results(of: [runs])
		#expect(results.map { $0.failure.map { "\($0.kind): \($0.details)" } } == [nil])
		#expect(results.flatMap { $0.laterFailures.map { "\($0.kind): \($0.details)" } } == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func valueOraclePlan_comparesNestRootsBuildWithTreeBuiltByHand_forSeed576() {
		// Seed 576 draws the shape plainly: two cycles, a required receive, and `NestInner` opening the second cycle before
		// it closes the first. A generator that passed `nestLabel` only between a function and the scopes that close a
		// cycle on it handed the `NestReader` beneath `NestRedeclarer` the root's `nestLabel`, which this pair reports.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: 576)

		#expect(Self.propertyDeclarations(of: "S576_NestRoot", in: fixture) == [
			"@Instantiated let nestLabel: S576_NestLabel",
			"@Instantiated let nestOuterBuilder: Instantiator<S576_NestOuter>",
		])
		#expect(Self.propertyDeclarations(of: "S576_NestOuter", in: fixture) == [
			"@Instantiated let nestInnerBuilder: Instantiator<S576_NestInner>",
			"@Instantiated let nestReaderBuilder: Instantiator<S576_NestReader>",
		])
		#expect(Self.propertyDeclarations(of: "S576_NestInner", in: fixture) == [
			"@Instantiated let nestRedeclarerBuilder: Instantiator<S576_NestRedeclarer>",
			"@Instantiated let nestOuterBuilder: Instantiator<S576_NestOuter>",
		])
		#expect(Self.propertyDeclarations(of: "S576_NestRedeclarer", in: fixture) == [
			"@Instantiated let nestLabel: S576_NestLabel",
			"@Instantiated let nestInnerBuilder: Instantiator<S576_NestInner>",
		])
		#expect(Self.propertyDeclarations(of: "S576_NestReader", in: fixture) == [
			"@Received let nestLabel: S576_NestLabel",
		])
		let plan = GraphFuzzerValueOraclePlan(fixture: fixture, generatedFiles: [:])
		#expect(plan.nestedCyclePair == DifferentialValueProbePair(
			name: "S576_NestRoot() against a tree built by hand",
			featureExpression: "S576_NestRoot()",
			knownRightExpression: "S576_ZNestMirror.build()",
		))
		#expect(plan.valueOracleFixture(storingEveryParameter: false).swiftFileContent.last == """
		// file: S576_ZNestMirror.swift
		enum S576_ZNestMirror {
			static func build() -> S576_NestRoot {
				func outer(nestLabel: S576_NestLabel) -> S576_NestOuter {
					S576_NestOuter(
						nestInnerBuilder: Instantiator<S576_NestInner> { inner(nestLabel: nestLabel) },
						nestReaderBuilder: Instantiator<S576_NestReader> { S576_NestReader(nestLabel: nestLabel) }
					)
				}
				func inner(nestLabel: S576_NestLabel) -> S576_NestInner {
					S576_NestInner(
						nestRedeclarerBuilder: Instantiator<S576_NestRedeclarer> { redeclarer() },
						nestOuterBuilder: Instantiator<S576_NestOuter> { outer(nestLabel: nestLabel) }
					)
				}
				func redeclarer() -> S576_NestRedeclarer {
					let nestLabel = S576_NestLabel()
					return S576_NestRedeclarer(
						nestLabel: nestLabel,
						nestInnerBuilder: Instantiator<S576_NestInner> { inner(nestLabel: nestLabel) }
					)
				}
				let nestLabel = S576_NestLabel()
				return S576_NestRoot(nestLabel: nestLabel, nestOuterBuilder: Instantiator<S576_NestOuter> { outer(nestLabel: nestLabel) })
			}
		}

		""")
	}

	@Test
	func corpusValueOracleCounts_compareTenNestedCyclePairs_whenPinsAreRead() {
		// The pair stands in for unit tests of the draw's shapes only while the value oracle compares it in at least ten
		// graphs the tool accepts, which the corpus runs pin exactly.
		#expect(SafeDIToolGraphFuzzerTests.corpusValueOracleCounts.nestedCyclePairCount >= SafeDIToolGraphFuzzerTests.gatingDrawJudgedGraphFloor)
	}

	// MARK: Private

	/// A shape of the draw, read from a graph's source.
	private enum Shape: String, CaseIterable {
		/// Every graph that draws the tree.
		case drawn
		/// `NestInner` declares the instantiator that closes the first cycle before the one that opens the second.
		case closesFirstCycleFirst
		/// `NestThird` sits between `NestInner` and `NestRedeclarer`, which builds it again.
		case thirdCycle
		/// `NestReader` receives `nestLabel` only if available, and `NestRoot` declares none.
		case receivedOnlyIfAvailable
		/// Every instantiator of the tree is a `SendableInstantiator`.
		case sendable
	}

	private static let drawnShapeCounts: [Shape: Int] = [
		.drawn: 179,
		.closesFirstCycleFirst: 92,
		.thirdCycle: 60,
		.receivedOnlyIfAvailable: 50,
		.sendable: 35,
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
		guard let shape = GraphFuzzerValueOraclePlan.NestedCycleShape(of: fixture) else { return [] }
		var shapes: Set<Shape> = [.drawn]
		if shape.closesFirstCycleFirst {
			shapes.insert(.closesFirstCycleFirst)
		}
		if shape.hasThirdCycle {
			shapes.insert(.thirdCycle)
		}
		if shape.receivesOnlyIfAvailable {
			shapes.insert(.receivedOnlyIfAvailable)
		}
		if shape.isSendable {
			shapes.insert(.sendable)
		}
		return shapes
	}
}
