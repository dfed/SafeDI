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
import Testing
@testable import SafeDICore
@testable import SafeDIToolTestSupport

struct SafeDIToolGraphFuzzerMockSharingTests {
	@Test
	func repetitions_namesEveryFunctionOfOneClass_whenMockDeclaresOneFunctionPerPlace() {
		#expect(GraphFuzzerMockSharedBuilders.repetitions(in: ["Host+SafeDIMock.swift": Self.onePerPlace]) == [
			GraphFuzzerMockSharedBuilders.Repetition(fileName: "Host+SafeDIMock.swift", mockedTypeName: "Host", mockName: "mock", functionNames: ["__safeDI_leaf", "__safeDI_leafBuilder", "__safeDI_leaf"]),
		])
	}

	@Test
	func repetitions_areEmpty_whenMockDeclaresOneFunctionPerClass() {
		#expect(GraphFuzzerMockSharedBuilders.repetitions(in: ["Host+SafeDIMock.swift": Self.onePerClass]) == [])
	}

	@Test
	func repetitions_areEmpty_whenFunctionsBuildOneTypeOtherwise() {
		// `Leaf` built from its override's builder at one place and with a part of another type at the other: two classes.
		let mock = """
		extension Host {
		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Host {
		        func __safeDI_leaf() -> Leaf {
		            return if let safeDIBuilder = safeDIOverrides.parentA.leaf.safeDIBuilder { safeDIBuilder(token) } else { Leaf(token: token) }
		        }
		        func __safeDI_leafOther() -> Leaf {
		            let part = Part()
		            return if let safeDIBuilder = safeDIOverrides.parentB.leaf.safeDIBuilder { safeDIBuilder(token, part) } else { Leaf(token: token, part: part) }
		        }
		        return Host(a: __safeDI_leaf(), b: __safeDI_leafOther())
		    }
		}
		"""
		#expect(GraphFuzzerMockSharedBuilders.repetitions(in: ["Host+SafeDIMock.swift": mock]) == [])
	}

	@Test
	func repetitions_areEmpty_whenFunctionsBuildOneTypeWithBuilderFunctionsOfOtherClassesBeneath() {
		// `Leaf` built twice, its `Part` read from `token` beneath one place and handed `nil` beneath the other: the two
		// functions that build `Leaf` read alike but call builder functions of two classes, so they are two classes too.
		let mock = """
		extension Host {
		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Host {
		        func __safeDI_part() -> Part {
		            Part(token: nil)
		        }
		        func __safeDI_leafBuilder() -> Leaf {
		            Leaf(part: __safeDI_part())
		        }
		        func __safeDI_part_() -> Part {
		            Part(token: token)
		        }
		        func __safeDI_leaf() -> Leaf {
		            Leaf(part: __safeDI_part_())
		        }
		        return Host(leafBuilder: Instantiator(__safeDI_leafBuilder), leaf: __safeDI_leaf())
		    }
		}
		"""
		#expect(GraphFuzzerMockSharedBuilders.repetitions(in: ["Host+SafeDIMock.swift": mock]) == [])
	}

	@Test
	func repetitions_nameEachRepeatedClass_whenTwoCallsDeclareAlikeFunctionsOfTheirOwn() {
		// Two calls of `Called`'s mock, each declaring its own `__safeDI_hole`, alike but for the override path.
		let mock = """
		extension Host {
		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Host {
		        func __safeDI_called() -> Called {
		            func __safeDI_hole() -> Hole {
		                Hole()
		            }
		            return Called.__safeDI_mock(hole: __safeDI_hole(), safeDIOverrides: safeDIOverrides.called)
		        }
		        func __safeDI_calledSecond() -> Called {
		            func __safeDI_hole() -> Hole {
		                Hole()
		            }
		            return Called.__safeDI_mock(hole: __safeDI_hole(), safeDIOverrides: safeDIOverrides.calledSecond)
		        }
		        return Host(called: __safeDI_called(), calledSecond: __safeDI_calledSecond())
		    }
		}
		"""
		#expect(GraphFuzzerMockSharedBuilders.repetitions(in: ["Host+SafeDIMock.swift": mock]).map(\.functionNames) == [
			["__safeDI_called", "__safeDI_calledSecond"],
			["__safeDI_hole", "__safeDI_hole"],
		])
	}

	@Test
	func repetitions_readOnlyMockBodies_whenAFileDeclaresOtherFunctions() {
		let file = """
		extension Host {
		    func first() -> Leaf { Leaf() }
		    func second() -> Leaf { Leaf() }
		}
		"""
		#expect(GraphFuzzerMockSharedBuilders.repetitions(in: ["Host+SafeDI.swift": file]) == [])
	}

	@Test
	func description_namesMockTypeFileAndFunctions() {
		let repetition = GraphFuzzerMockSharedBuilders.Repetition(fileName: "FuzzFeature.swift", mockedTypeName: "A", mockName: "__safeDI_mock", functionNames: ["__safeDI_a", "__safeDI_b"])
		#expect(repetition.description == "`__safeDI_mock` of `A` in `FuzzFeature.swift` declares 2 functions of one class: `__safeDI_a`, `__safeDI_b`")
	}

	@Test
	func repetitions_nameTheTypeEachMockExtends_whenOneFileHoldsSeveralMocks() {
		let file = Self.onePerPlace + "\n" + Self.onePerPlace.replacingOccurrences(of: "Host", with: "Other")
		#expect(GraphFuzzerMockSharedBuilders.repetitions(in: ["FuzzFeature.swift": file]).map(\.mockedTypeName) == ["Host", "Other"])
	}

	// MARK: Judgment

	@Test
	func repeatingRootCounts_countRootUnderLaidOut_whenLayoutSaysItLaidRootOut() {
		let repetitions = GraphFuzzerMockSharedBuilders.repetitions(in: ["Host+SafeDIMock.swift": Self.onePerPlace])
		#expect(GraphFuzzerMockSharedBuilders.repeatingRootCounts(of: repetitions, outcomesByMockedType: ["Host": "laidOut"]) == ["laidOut": 1])
	}

	@Test
	func repeatingRootCounts_countRootOnceUnderItsFallback_whenLayoutKeptWalkBodyOfRootRepeatingTwoClasses() {
		let repetitions = [
			GraphFuzzerMockSharedBuilders.Repetition(fileName: "Host+SafeDIMock.swift", mockedTypeName: "Host", mockName: "mock", functionNames: ["__safeDI_a", "__safeDI_a"]),
			GraphFuzzerMockSharedBuilders.Repetition(fileName: "Host+SafeDIMock.swift", mockedTypeName: "Host", mockName: "mock", functionNames: ["__safeDI_b", "__safeDI_b"]),
			GraphFuzzerMockSharedBuilders.Repetition(fileName: "Other+SafeDIMock.swift", mockedTypeName: "Other", mockName: "mock", functionNames: ["__safeDI_c", "__safeDI_c"]),
		]
		let outcomes = ["Host": "readUnresolved:token", "Other": "readUnresolved:note"]
		#expect(GraphFuzzerMockSharedBuilders.repeatingRootCounts(of: repetitions, outcomesByMockedType: outcomes) == ["readUnresolved": 2])
	}

	@Test
	func repeatingRootCounts_countRootAsUnreported_whenLayoutReportedNothingAboutIt() {
		let repetitions = GraphFuzzerMockSharedBuilders.repetitions(in: ["Host+SafeDIMock.swift": Self.onePerPlace])
		#expect(GraphFuzzerMockSharedBuilders.repeatingRootCounts(of: repetitions, outcomesByMockedType: ["Other": "laidOut"]) == ["unreported": 1])
	}

	@Test
	func fallbackName_keepsUnrecordedPlacesReasonAndDropsWhatNamesALabel() {
		#expect(GraphFuzzerMockSharedBuilders.fallbackName(of: "unrecorded:unplannedLines:rebinding+overrideExtraction") == "unrecorded:unplannedLines")
		#expect(GraphFuzzerMockSharedBuilders.fallbackName(of: "unrecorded:publicMockCall") == "unrecorded:publicMockCall")
		#expect(GraphFuzzerMockSharedBuilders.fallbackName(of: "readUnresolved:token") == "readUnresolved")
		#expect(GraphFuzzerMockSharedBuilders.fallbackName(of: "entersCycleWithEdge") == "entersCycleWithEdge")
		#expect(GraphFuzzerMockSharedBuilders.fallbackName(of: nil) == "unreported")
	}

	// MARK: Long run

	/// Counts, with the generator's layout on (`MockLowering.laysOutWithTypeKey`), over a corpus's seeds
	/// (`SAFEDI_MOCK_SHARING_FEATURES`, `…_STARTING_SEED`, `…_ITERATIONS`, a count or `corpus`), every mock root's outcome
	/// as the layout reports it (`MockLowering.typeKeyLayoutObserver`; `outcome` lines, which nothing pins) and the roots
	/// that repeat a class under each outcome (`repeats` lines), appended to `SAFEDI_MOCK_SHARING_REPORT` with each seed
	/// whose laid-out root repeats a class (`laid-out-repeats` lines), and, in a run of a whole corpus, checks the repeating
	/// roots against the corpus's pins (`repeatingRootCounts`), so a share the layout newly loses moves a pin.
	@Test(.enabled(if: ProcessInfo.processInfo.environment["SAFEDI_MOCK_SHARING"] == "1", "Set SAFEDI_MOCK_SHARING=1 to run"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func longRun_countsRootsThatRepeatAClassByLayoutOutcome_whenEnabledByEnvironment() async throws {
		let environment = ProcessInfo.processInfo.environment
		let featureNames = environment["SAFEDI_MOCK_SHARING_FEATURES"] ?? ""
		let features = Set(featureNames.split(separator: ",").compactMap { GraphFuzzerGeneratorFeature(rawValue: String($0)) })
		let corpusSeedCount = UInt64(Self.corpusSeedCounts[featureNames] ?? 0)
		let startingSeed = UInt64(environment["SAFEDI_MOCK_SHARING_STARTING_SEED"] ?? "0") ?? 0
		let iterationsText = environment["SAFEDI_MOCK_SHARING_ITERATIONS"] ?? "100"
		let iterations = iterationsText == "corpus" ? corpusSeedCount : UInt64(iterationsText) ?? 100
		let report = GraphFuzzerReport(path: environment["SAFEDI_MOCK_SHARING_REPORT"] ?? "")
		var accepted = 0
		var laidOutRepeats = [(seed: UInt64, repetition: GraphFuzzerMockSharedBuilders.Repetition)]()
		var repeatingRootCounts = [String: Int]()
		var rootOutcomeCounts = [String: Int]()
		try await withThrowingTaskGroup(of: (UInt64, SeedJudgment?).self) { group in
			for seed in startingSeed..<(startingSeed + iterations) {
				group.addTask {
					try await (seed, Self.judgment(of: GraphFuzzerGenerator.fixture(forSeed: seed, features: features)))
				}
			}
			for try await (seed, judgment) in group {
				guard let judgment else { continue }
				accepted += 1
				for (name, count) in judgment.rootOutcomeCounts {
					rootOutcomeCounts[name, default: 0] += count
				}
				for (name, count) in judgment.repeatingRootCounts {
					repeatingRootCounts[name, default: 0] += count
				}
				if let repetition = judgment.firstLaidOutRepetition {
					laidOutRepeats.append((seed, repetition))
				}
			}
		}
		laidOutRepeats.sort { $0.seed < $1.seed }
		for (seed, repetition) in laidOutRepeats {
			report.append("laid-out-repeats \(seed) \(repetition)")
		}
		for name in rootOutcomeCounts.keys.sorted() {
			report.append("outcome \(name) \(rootOutcomeCounts[name, default: 0])")
		}
		for name in repeatingRootCounts.keys.sorted() {
			report.append("repeats \(name) \(repeatingRootCounts[name, default: 0])")
		}
		report.append("summary mock-sharing seeds=\(startingSeed)..<\(startingSeed + iterations) accepted=\(accepted) roots=\(rootOutcomeCounts.values.reduce(0, +)) repeating-roots=\(repeatingRootCounts.values.reduce(0, +))")
		if startingSeed == 0, iterations == corpusSeedCount {
			#expect(repeatingRootCounts == Self.repeatingRootCounts[featureNames], "pins of corpus `\(featureNames)`: \(repeatingRootCounts.sorted { $0.key < $1.key })")
		}
	}

	/// What one accepted seed's mocks show: the roots under each outcome, the roots that repeat a class under each, and the
	/// first repetition of a root the layout laid out.
	private struct SeedJudgment {
		var rootOutcomeCounts = [String: Int]()
		var repeatingRootCounts = [String: Int]()
		var firstLaidOutRepetition: GraphFuzzerMockSharedBuilders.Repetition?
	}

	/// What the generator, with its layout on, generates for `fixture`, judged against each mock root's outcome as the layout
	/// reports it, or `nil` where the tool rejects the graph.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func judgment(of fixture: GraphFuzzerFixture) async throws -> SeedJudgment? {
		let (stream, continuation) = AsyncStream.makeStream(of: (mockedType: String, outcome: String).self)
		let outcome = try await MockLowering.$laysOutWithTypeKey.withValue(true) {
			try await MockLowering.$typeKeyLayoutObserver.withValue({ mockedType, outcome in continuation.yield((mockedType, outcome)) }) {
				try await GraphFuzzerOracle.toolOutcome(of: fixture)
			}
		}
		continuation.finish()
		var outcomesByMockedType = [String: String]()
		for await (mockedType, outcome) in stream {
			outcomesByMockedType[mockedType] = outcome
		}
		switch outcome {
		case .rejected:
			return nil
		case let .accepted(generatedFiles, _):
			let repetitions = GraphFuzzerMockSharedBuilders.repetitions(in: generatedFiles)
			var judgment = SeedJudgment()
			for outcome in outcomesByMockedType.values {
				judgment.rootOutcomeCounts[GraphFuzzerMockSharedBuilders.fallbackName(of: outcome), default: 0] += 1
			}
			judgment.repeatingRootCounts = GraphFuzzerMockSharedBuilders.repeatingRootCounts(of: repetitions, outcomesByMockedType: outcomesByMockedType)
			judgment.firstLaidOutRepetition = repetitions.first { outcomesByMockedType[$0.mockedTypeName] == "laidOut" }
			return judgment
		}
	}

	/// Each corpus's seed count, by its `SAFEDI_MOCK_SHARING_FEATURES`.
	static let corpusSeedCounts = [
		"": SafeDIToolGraphFuzzerTests.corpusSeedCount,
		"generateDependencyTree": SafeDIToolGraphFuzzerTests.seamCorpusSeedCount,
		"generateMockPublic": SafeDIToolGraphFuzzerTests.publicMockCorpusSeedCount,
	]

	/// For each corpus, by its `SAFEDI_MOCK_SHARING_FEATURES`, the mock roots that repeat a class under each of the layout's
	/// outcomes, from a run of the whole corpus.
	static let repeatingRootCounts: [String: [String: Int]] = [
		"": [
			"engineRefused": 6,
			"laidOut": 23,
			"readUnresolved": 39,
			"unrecorded:loop": 1,
			"unrecorded:namedApart": 5,
			"unrecorded:unplannedLines": 46,
		],
		"generateDependencyTree": [
			"laidOut": 6,
			"readUnresolved": 60,
			"unrecorded:unplannedLines": 9,
		],
		"generateMockPublic": [
			"laidOut": 69,
			"readUnresolved": 1,
			"unrecorded:loop": 3,
			"unrecorded:namedApart": 11,
			"unrecorded:unplannedLines": 4,
			"unreported": 242,
		],
	]

	// MARK: Generated code

	/// A mock as the walk lays it out, one function per place: `Leaf` is built under `ParentA`, through `ParentB`'s
	/// instantiator, and under `ParentC`, each reading its own override path.
	private static let onePerPlace = """
	#if DEBUG
	extension Host {
	    static func mock(
	        safeDIOverrides: SafeDIOverrides = .init()
	    ) -> Host {
	        let token = if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
	        func __safeDI_parentA() -> ParentA {
	            func __safeDI_leaf() -> Leaf {
	                let part = if let safeDIBuilder = safeDIOverrides.parentA.leaf.part { safeDIBuilder() } else { Part() }
	                return if let safeDIBuilder = safeDIOverrides.parentA.leaf.safeDIBuilder { safeDIBuilder(token, part) } else { Leaf(token: token, part: part) }
	            }
	            let leaf: Leaf = __safeDI_leaf()
	            return if let safeDIBuilder = safeDIOverrides.parentA.safeDIBuilder { safeDIBuilder(leaf) } else { ParentA(leaf: leaf) }
	        }
	        let parentA: ParentA = __safeDI_parentA()
	        func __safeDI_parentB() -> ParentB {
	            func __safeDI_leafBuilder() -> Leaf {
	                let part = if let safeDIBuilder = safeDIOverrides.parentB.leafBuilder.part { safeDIBuilder() } else { Part() }
	                return if let safeDIBuilder = safeDIOverrides.parentB.leafBuilder.safeDIBuilder { safeDIBuilder(token, part) } else { Leaf(token: token, part: part) }
	            }
	            let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
	            return if let safeDIBuilder = safeDIOverrides.parentB.safeDIBuilder { safeDIBuilder(leafBuilder) } else { ParentB(leafBuilder: leafBuilder) }
	        }
	        let parentB: ParentB = __safeDI_parentB()
	        func __safeDI_parentC() -> ParentC {
	            func __safeDI_leaf() -> Leaf {
	                let part = if let safeDIBuilder = safeDIOverrides.parentC.leaf.part { safeDIBuilder() } else { Part() }
	                return if let safeDIBuilder = safeDIOverrides.parentC.leaf.safeDIBuilder { safeDIBuilder(token, part) } else { Leaf(token: token, part: part) }
	            }
	            let leaf: Leaf = __safeDI_leaf()
	            return if let safeDIBuilder = safeDIOverrides.parentC.safeDIBuilder { safeDIBuilder(leaf) } else { ParentC(leaf: leaf) }
	        }
	        let parentC: ParentC = __safeDI_parentC()
	        return Host(token: token, parentA: parentA, parentB: parentB, parentC: parentC)
	    }
	}
	#endif
	"""

	/// The same mock with one function per class, each handed its place's configuration.
	private static let onePerClass = """
	#if DEBUG
	extension Host {
	    static func mock(
	        safeDIOverrides: SafeDIOverrides = .init()
	    ) -> Host {
	        let token = if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
	        func __safeDI_leaf(__safeDI_overrides: Leaf.SafeDIMockConfiguration) -> Leaf {
	            let part = if let safeDIBuilder = __safeDI_overrides.part { safeDIBuilder() } else { Part() }
	            return if let safeDIBuilder = __safeDI_overrides.safeDIBuilder { safeDIBuilder(token, part) } else { Leaf(token: token, part: part) }
	        }
	        func __safeDI_parentA_(__safeDI_overrides: ParentA.SafeDIMockConfiguration) -> ParentA {
	            let leaf: Leaf = __safeDI_leaf(__safeDI_overrides: __safeDI_overrides.leaf)
	            return if let safeDIBuilder = __safeDI_overrides.safeDIBuilder { safeDIBuilder(leaf) } else { ParentA(leaf: leaf) }
	        }
	        let parentA: ParentA = __safeDI_parentA_(__safeDI_overrides: safeDIOverrides.parentA)
	        func __safeDI_parentB_(__safeDI_overrides: ParentB.SafeDIMockConfiguration) -> ParentB {
	            let leafBuilder = Instantiator<Leaf> { __safeDI_leaf(__safeDI_overrides: __safeDI_overrides.leafBuilder) }
	            return if let safeDIBuilder = __safeDI_overrides.safeDIBuilder { safeDIBuilder(leafBuilder) } else { ParentB(leafBuilder: leafBuilder) }
	        }
	        let parentB: ParentB = __safeDI_parentB_(__safeDI_overrides: safeDIOverrides.parentB)
	        func __safeDI_parentC_(__safeDI_overrides: ParentC.SafeDIMockConfiguration) -> ParentC {
	            let leaf: Leaf = __safeDI_leaf(__safeDI_overrides: __safeDI_overrides.leaf)
	            return if let safeDIBuilder = __safeDI_overrides.safeDIBuilder { safeDIBuilder(leaf) } else { ParentC(leaf: leaf) }
	        }
	        let parentC: ParentC = __safeDI_parentC_(__safeDI_overrides: safeDIOverrides.parentC)
	        return Host(token: token, parentA: parentA, parentB: parentB, parentC: parentC)
	    }
	}
	#endif
	"""
}
