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

/// The base corpus's draw of a mocked type two mocks build (`addingMockedTypeTwoMocksBuild`), and the oracle that judges
/// which of those mocks build it with the one builder shared per type (`GraphFuzzerToolRuns.sharedMockBuilderFailure`).
struct SafeDIToolGraphFuzzerSharedMockBuilderTests {
	@Test
	func baseCorpus_drawsEachShapeOfMockedTypeTwoMocksBuild_inPinnedNumberOfGraphs() {
		// Each shape lands in exactly the pinned number of the corpus's graphs, read from their source, and in at least ten:
		// the draw is deterministic, so a change in a shape's share is a reviewed diff.
		var counts = [GraphFuzzerFeature: Int]()
		var smokeFeatures = Set<GraphFuzzerFeature>()
		for seed in 0..<UInt64(SafeDIToolGraphFuzzerTests.corpusSeedCount) {
			let features = GraphFuzzerFeature.features(of: GraphFuzzerGenerator.fixture(forSeed: seed)).intersection(Self.drawFeatures)
			for feature in features {
				counts[feature, default: 0] += 1
			}
			if SafeDIToolGraphFuzzerTests.smokeSeeds.contains(seed) {
				smokeFeatures.formUnion(features)
			}
		}
		for feature in Self.drawFeatures.sorted() {
			#expect(counts[feature, default: 0] == Self.drawnFeatureCounts[feature], "\(feature.rawValue) drawn in \(counts[feature, default: 0]) graphs")
			#expect(counts[feature, default: 0] >= SafeDIToolGraphFuzzerTests.gatingDrawJudgedGraphFloor, "\(feature.rawValue) drawn in fewer than ten graphs")
		}
		// The smoke batch must show every base feature in a graph the tool accepts, which the smoke test checks.
		#expect(smokeFeatures == Set(Self.drawFeatures))
	}

	@Test
	func draw_readsEachShape_fromFixtureSource() {
		let draw = GraphFuzzerSharedMockBuilderDraw(fixture: Self.fixture(screenAttributes: "@MainActor", screenIsMainActor: false, secondAttributes: nil))

		#expect(draw?.screenName == "S1_ShareScreen")
		#expect(draw?.screenMockAttributes == "@MainActor")
		#expect(draw?.screenInitializerIsNonisolated == false)
		#expect(draw?.callerMockAttributes == ["S1_ShareFirst": .some("@MainActor"), "S1_ShareSecond": String?.none])
		#expect(draw?.firstReachesThroughUnmockedType == true)
		#expect(GraphFuzzerSharedMockBuilderDraw(fixture: Self.fixture(screenAttributes: nil, screenIsMainActor: true, secondAttributes: nil))?.screenInitializerIsNonisolated == true)
	}

	@Test
	func sharedMockBuilderFailure_isNil_whenMocksOfMatchingAttributesCallOneBuilderAndOthersBuildInline() {
		let fixture = Self.fixture(screenAttributes: "@MainActor", screenIsMainActor: false, secondAttributes: nil)
		let runs = Self.runs(of: fixture, generatedFiles: [
			"S1_ShareScreen+SafeDIMock.swift": Self.screenMock(declaringBuilder: true),
			"S1_ShareFirst+SafeDIMock.swift": "let shareScreen = S1_ShareScreen.__safeDI_build_0a1b2c3d(shareService: shareService)",
			"S1_ShareSecond+SafeDIMock.swift": "return if let safeDIBuilder = configuration.safeDIBuilder { safeDIBuilder(shareService, shareModel) } else { S1_ShareScreen(shareService: shareService, shareModel: shareModel) }",
		])

		#expect(runs.sharedMockBuilderFailure == nil)
	}

	@Test
	func sharedMockBuilderFailure_reportsEachMock_whenMocksBuildTypeWithoutItsSharedBuilder() {
		// The hand mutation the oracle exists for: a mock that builds the type inline where the builder is shared, a second
		// builder, and a mock of other attributes that calls the builder.
		let fixture = Self.fixture(screenAttributes: "@MainActor", screenIsMainActor: false, secondAttributes: nil)
		let failure = Self.runs(of: fixture, generatedFiles: [
			"S1_ShareScreen+SafeDIMock.swift": Self.screenMock(declaringBuilder: true) + "\n" + Self.screenMock(declaringBuilder: true),
			"S1_ShareFirst+SafeDIMock.swift": "func __safeDI_shareScreen() -> S1_ShareScreen { S1_ShareScreen(shareService: shareService, shareModel: shareModel) }",
			"S1_ShareSecond+SafeDIMock.swift": "let shareScreen = S1_ShareScreen.__safeDI_build_0a1b2c3d(shareService: shareService)",
		]).sharedMockBuilderFailure

		#expect(failure?.kind == .mockedTypeNotBuiltWithSharedBuilder)
		#expect(failure?.details.split(separator: "\n").prefix(3) == [
			"`S1_ShareScreen+SafeDIMock.swift` declares 2 builders of `S1_ShareScreen`, not one.",
			"`S1_ShareFirst+SafeDIMock.swift` builds `S1_ShareScreen` without its shared builder.",
			"`S1_ShareSecond+SafeDIMock.swift` calls `S1_ShareScreen`'s shared builder, which it builds inline since its mock spells other attributes.",
		])
	}

	@Test
	func sharedMockBuilderFailure_reportsBuilder_whenTypesInitializerIsNonisolated() {
		let fixture = Self.fixture(screenAttributes: nil, screenIsMainActor: true, secondAttributes: "@MainActor")
		let failure = Self.runs(of: fixture, generatedFiles: [
			"S1_ShareScreen+SafeDIMock.swift": Self.screenMock(declaringBuilder: true),
			"S1_ShareFirst+SafeDIMock.swift": "let shareScreen = S1_ShareScreen(shareService: shareService, shareModel: shareModel)",
			"S1_ShareSecond+SafeDIMock.swift": "let shareScreen = S1_ShareScreen(shareService: shareService, shareModel: shareModel)",
		]).sharedMockBuilderFailure

		#expect(failure?.details.split(separator: "\n").first == "`S1_ShareScreen+SafeDIMock.swift` declares a builder of a type whose initializer is `nonisolated`, which every mock builds inline.")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func sharedMockBuilderFailure_isNil_forEachSeedOfDraw() async throws {
		// One seed of each shape, run through the tool: written before the generator shares builders, so it fails until then.
		for seed in Self.seedsOfEachShape {
			let fixture = GraphFuzzerGenerator.fixture(forSeed: seed)
			let outcome = try await GraphFuzzerOracle.toolOutcome(of: fixture)
			guard case .accepted = outcome else {
				Issue.record("seed \(seed) is rejected: \(outcome)")
				continue
			}
			let runs = GraphFuzzerToolRuns(fixture: fixture, firstOutcome: outcome, secondOutcome: outcome)

			#expect(runs.sharedMockBuilderFailure == nil, "seed \(seed): \(runs.sharedMockBuilderFailure?.details.split(separator: "\n").prefix(3).joined(separator: "\n") ?? "")")
		}
	}

	// MARK: Private

	private static let drawFeatures: [GraphFuzzerFeature] = [
		.mockedTypeTwoMocksBuild,
		.mockedTypeTwoMocksBuildBeneathUnmockedType,
		.mockedTypeBuiltByMockSpellingOtherAttributes,
		.mockedTypeWithNonisolatedInitializer,
	]

	private static let drawnFeatureCounts: [GraphFuzzerFeature: Int] = [
		.mockedTypeTwoMocksBuild: 1_009,
		.mockedTypeTwoMocksBuildBeneathUnmockedType: 509,
		.mockedTypeBuiltByMockSpellingOtherAttributes: 182,
		.mockedTypeWithNonisolatedInitializer: 267,
	]

	/// The smoke seeds the tool accepts that draw the shape: `ShareFirst` beneath `ShareMiddle` and a `nonisolated` initializer
	/// (19), and `mockAttributes` `ShareSecond`'s mock does not spell (520). Smoke seeds 70 and 86 draw it in graphs the tool
	/// rejects for their other types.
	private static let seedsOfEachShape: [UInt64] = [19, 520]

	private static func runs(of fixture: GraphFuzzerFixture, generatedFiles: [String: String]) -> GraphFuzzerToolRuns {
		let outcome = GraphFuzzerToolOutcome.accepted(generatedFiles: generatedFiles, warnings: [])
		return GraphFuzzerToolRuns(fixture: fixture, firstOutcome: outcome, secondOutcome: outcome)
	}

	private static func screenMock(declaringBuilder: Bool) -> String {
		"""
		extension S1_ShareScreen {
			\(declaringBuilder ? "@MainActor static func __safeDI_build_0a1b2c3d(shareService: S1_ShareService) -> S1_ShareScreen {" : "func other() {")
			}
		}
		"""
	}

	/// The draw's types as the fuzzer writes them, with `ShareFirst` reaching `ShareScreen` through `ShareMiddle`.
	private static func fixture(screenAttributes: String?, screenIsMainActor: Bool, secondAttributes: String?) -> GraphFuzzerFixture {
		func arguments(_ attributes: String?) -> String {
			(attributes.map { "mockAttributes: \"\($0)\", " } ?? "") + "generateMock: true"
		}
		return GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(\(arguments(screenAttributes)))
			\(screenIsMainActor ? "@MainActor " : "")public final class S1_ShareScreen: Instantiable {
				\(screenIsMainActor ? "nonisolated " : "")public init(shareService: S1_ShareService) {
					self.shareService = shareService
				}

				@Received let shareService: S1_ShareService
			}
			""",
			"""
			@Instantiable
			public final class S1_ShareMiddle: Instantiable {
				public init(shareScreen: S1_ShareScreen) {
					self.shareScreen = shareScreen
				}

				@Instantiated let shareScreen: S1_ShareScreen
			}
			""",
			"""
			@Instantiable(\(arguments(screenAttributes)))
			public final class S1_ShareFirst: Instantiable {
				public init(shareMiddle: S1_ShareMiddle) {
					self.shareMiddle = shareMiddle
				}

				@Instantiated let shareMiddle: S1_ShareMiddle
			}
			""",
			"""
			@Instantiable(\(arguments(secondAttributes)))
			public final class S1_ShareSecond: Instantiable {
				public init(shareScreen: S1_ShareScreen) {
					self.shareScreen = shareScreen
				}

				@Instantiated let shareScreen: S1_ShareScreen
			}
			""",
		])
	}
}
