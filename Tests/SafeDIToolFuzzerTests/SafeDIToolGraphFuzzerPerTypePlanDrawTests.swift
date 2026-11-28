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

/// The base corpus's draw of screens laid out from the per-type plan (`addingScreensLaidOutFromPerTypePlan`).
struct SafeDIToolGraphFuzzerPerTypePlanDrawTests {
	@Test
	func baseCorpus_drawsEachShapeOfScreensLaidOutFromPerTypePlan_inPinnedNumberOfGraphs() {
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
	func toolRuns_layOutPlanRootFromItsPlan_inEveryAcceptedGraphOfTheFirstDrawnSeeds() async throws {
		// The draw stands in for the corpus's roots laid out from their plan only while the tool lays `PlanRoot` out from its
		// plan, which no shape the draw holds keeps on today's tree: a root kept there is judged as before by the corpus's
		// other oracles, so a draw that drifts onto it would gate nothing new.
		let drawnSeeds = (0..<UInt64(SafeDIToolGraphFuzzerTests.corpusSeedCount)).lazy
			.filter { Self.shapes(of: GraphFuzzerGenerator.fixture(forSeed: $0)).contains(.drawn) }
			.prefix(Self.admissionSeedCount)
		var acceptedSeeds = [UInt64]()
		for seed in drawnSeeds {
			let fixture = GraphFuzzerGenerator.fixture(forSeed: seed)
			let (stream, continuation) = AsyncStream.makeStream(of: (String, RootTreeChoiceObservation.PerPathReason?).self)
			// The draw's trees are within the limit the tool ships with, so the limit is set to none: the tool then lays out
			// from its plan every root it would past the limit.
			let outcome = try await RootTreeChoiceObservation.$scopeGeneratorLimitOverride.withValue(0) {
				try await RootTreeChoiceObservation.$observer.withValue(TaskLocalFunction { root, perPathReason in
					continuation.yield((root, perPathReason))
				}) {
					try await GraphFuzzerOracle.toolOutcome(of: fixture)
				}
			}
			continuation.finish()
			var planRootReasons = [RootTreeChoiceObservation.PerPathReason?]()
			for await (root, perPathReason) in stream where root.hasSuffix("PlanRoot") {
				planRootReasons.append(perPathReason)
			}
			switch outcome {
			case let .rejected(diagnostics):
				// Another draw of the graph has the tool reject it, never this one, which holds no shape the tool rejects.
				#expect(!diagnostics.contains(GraphFuzzerFixture.typeNamePrefix(forSeed: seed) + "Plan"), "seed \(seed) is rejected over the draw's types: \(diagnostics)")
				continue
			case .accepted:
				break
			}
			acceptedSeeds.append(seed)
			#expect(planRootReasons.count == 1, "seed \(seed) chose \(planRootReasons.count) trees for PlanRoot")
			for reason in planRootReasons {
				#expect(reason == nil, "seed \(seed) keeps PlanRoot on today's tree: \(reason.map(\.rawValue) ?? "")")
			}
		}
		#expect(acceptedSeeds.count >= SafeDIToolGraphFuzzerTests.gatingDrawJudgedGraphFloor, "accepted seeds: \(acceptedSeeds)")
	}

	// MARK: Private

	/// A shape of the draw, read from a graph's source.
	private enum Shape: String, CaseIterable {
		/// Every graph that draws the tree.
		case drawn
		/// A screen opens a screen besides the next one around the ring.
		case opensScreenBeyondRing
		/// A screen forwards a value, which its opener's instantiator is called with.
		case forwardsValue
		/// A screen builds a pane by value, which opens a screen through an instantiator.
		case buildsPaneOnCycle
		/// A screen builds `PlanDetail` by value, a tree outside the cycle.
		case buildsTreeOutsideCycle
		/// A screen receives a model `PlanScreen0` declares again each time the cycle builds it.
		case receivesModelCycleDeclaresAgain
		/// A screen receives a service only the root declares.
		case receivesServiceOnlyRootDeclares
		/// A screen builds `PlanJob` through a `SendableInstantiator`.
		case buildsJobInSendableFunction
		/// `PlanJob` receives a service, which the `@Sendable` builder function that builds it captures.
		case sendableFunctionCapturesService
	}

	private static let drawnShapeCounts: [Shape: Int] = [
		.drawn: 227,
		.opensScreenBeyondRing: 168,
		.forwardsValue: 147,
		.buildsPaneOnCycle: 106,
		.buildsTreeOutsideCycle: 70,
		.receivesModelCycleDeclaresAgain: 207,
		.receivesServiceOnlyRootDeclares: 212,
		.buildsJobInSendableFunction: 51,
		.sendableFunctionCapturesService: 23,
	]

	/// How many of the first drawn seeds the tool runs over, more than the floor, since another draw of the graph can have
	/// the tool reject it.
	private static let admissionSeedCount = 28

	private static func shapes(of fixture: GraphFuzzerFixture) -> Set<Shape> {
		let prefix = GraphFuzzerFixture.typeNamePrefix(forSeed: fixture.seed)
		var shapes = Set<Shape>()
		var currentTypeName = ""
		var screenBuildersOfCurrentType = 0
		func endType() {
			if screenBuildersOfCurrentType > 1 {
				shapes.insert(.opensScreenBeyondRing)
			}
			screenBuildersOfCurrentType = 0
		}
		for line in fixture.swiftFileContent.flatMap(GraphFuzzerSourceLine.lines(of:)) {
			switch line {
			case let .typeDeclaration(name):
				endType()
				currentTypeName = name
				if name == "\(prefix)PlanRoot" {
					shapes.insert(.drawn)
				}
			case let .property(attribute, label, _):
				if currentTypeName == "\(prefix)PlanJob", attribute == "@Received", label.hasPrefix("planService") {
					shapes.insert(.sendableFunctionCapturesService)
				}
				guard currentTypeName.hasPrefix("\(prefix)PlanScreen") else { continue }
				if attribute == "@Instantiated", label.hasPrefix("planScreen") {
					screenBuildersOfCurrentType += 1
				} else if attribute == "@Forwarded" {
					shapes.insert(.forwardsValue)
				} else if attribute == "@Instantiated", label == "planJobBuilder" {
					shapes.insert(.buildsJobInSendableFunction)
				} else if attribute == "@Instantiated", label.hasPrefix("planPane") {
					shapes.insert(.buildsPaneOnCycle)
				} else if attribute == "@Instantiated", label == "planDetail" {
					shapes.insert(.buildsTreeOutsideCycle)
				} else if attribute == "@Received", label.hasPrefix("planModel") {
					shapes.insert(.receivesModelCycleDeclaresAgain)
				} else if attribute == "@Received", label.hasPrefix("planService") {
					shapes.insert(.receivesServiceOnlyRootDeclares)
				}
			case .instantiableAttribute, .instantiateMethod, .other:
				break
			}
		}
		endType()
		return shapes
	}
}
