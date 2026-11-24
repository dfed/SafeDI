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
@testable import SafeDIToolTestSupport

struct SafeDIToolGraphFuzzerMockSharingTests {
	@Test
	func repetitions_namesEveryFunctionOfOneClass_whenMockDeclaresOneFunctionPerPlace() {
		#expect(GraphFuzzerMockSharedBuilders.repetitions(in: ["Host+SafeDIMock.swift": Self.onePerPlace]) == [
			GraphFuzzerMockSharedBuilders.Repetition(fileName: "Host+SafeDIMock.swift", mockName: "mock", functionNames: ["__safeDI_leaf", "__safeDI_leafBuilder", "__safeDI_leaf"]),
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
	func description_namesMockFileAndFunctions() {
		let repetition = GraphFuzzerMockSharedBuilders.Repetition(fileName: "A+SafeDIMock.swift", mockName: "__safeDI_mock", functionNames: ["__safeDI_a", "__safeDI_b"])
		#expect(repetition.description == "`__safeDI_mock` in `A+SafeDIMock.swift` declares 2 functions of one class: `__safeDI_a`, `__safeDI_b`")
	}

	@Test
	func mockSharingFailure_judgesOnlyWhereAsked() {
		let outcome = GraphFuzzerToolOutcome.accepted(generatedFiles: ["Host+SafeDIMock.swift": Self.onePerPlace], warnings: [])
		let runs = GraphFuzzerToolRuns(fixture: GraphFuzzerFixture(seed: 7, swiftFileContent: []), firstOutcome: outcome, secondOutcome: outcome)
		#expect(runs.mockSharingFailure(isJudged: false) == nil)
		#expect(runs.mockSharingFailure(isJudged: true)?.kind == .mockSharedBodyRepeatsClass)
		#expect(runs.mockSharingFailure(isJudged: true)?.details.hasPrefix("`mock` in `Host+SafeDIMock.swift` declares 3 functions of one class: `__safeDI_leaf`, `__safeDI_leafBuilder`, `__safeDI_leaf`\n") == true)
	}

	// MARK: Long run

	/// Judges a built tool, `SAFEDI_MOCK_SHARING_TOOL`, over a corpus's seeds (`SAFEDI_MOCK_SHARING_FEATURES`,
	/// `…_STARTING_SEED`, `…_ITERATIONS`), appending to `SAFEDI_MOCK_SHARING_REPORT` each graph whose mocks repeat a class
	/// and a summary. A tool that shares fails on each such graph; the run asks nothing of a tool that does not.
	@Test(.enabled(if: ProcessInfo.processInfo.environment["SAFEDI_MOCK_SHARING_TOOL"] != nil, "Set SAFEDI_MOCK_SHARING_TOOL to run"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func longRun_reportsEveryRepeatedClass_whenEnabledByEnvironment() async throws {
		let environment = ProcessInfo.processInfo.environment
		let tool = URL(fileURLWithPath: environment["SAFEDI_MOCK_SHARING_TOOL", default: ""])
		let features = Set((environment["SAFEDI_MOCK_SHARING_FEATURES"] ?? "").split(separator: ",").compactMap { GraphFuzzerGeneratorFeature(rawValue: String($0)) })
		let startingSeed = UInt64(environment["SAFEDI_MOCK_SHARING_STARTING_SEED"] ?? "0") ?? 0
		let iterations = UInt64(environment["SAFEDI_MOCK_SHARING_ITERATIONS"] ?? "100") ?? 100
		let requiresSharing = environment["SAFEDI_MOCK_SHARING_REQUIRED"] == "1"
		let report = GraphFuzzerReport(path: environment["SAFEDI_MOCK_SHARING_REPORT"] ?? "")
		var accepted = 0
		var repeating = [(seed: UInt64, repetitions: [GraphFuzzerMockSharedBuilders.Repetition])]()
		try await withThrowingTaskGroup(of: (UInt64, [GraphFuzzerMockSharedBuilders.Repetition]?).self) { group in
			for seed in startingSeed..<(startingSeed + iterations) {
				group.addTask {
					try await (seed, GraphFuzzerMockSharedBuilders.repetitions(generatedBy: tool, for: GraphFuzzerGenerator.fixture(forSeed: seed, features: features)))
				}
			}
			for try await (seed, repetitions) in group {
				guard let repetitions else { continue }
				accepted += 1
				if !repetitions.isEmpty {
					repeating.append((seed, repetitions))
				}
			}
		}
		repeating.sort { $0.seed < $1.seed }
		for (seed, repetitions) in repeating {
			report.append("repeats \(seed) \(repetitions.count) \(repetitions[0])")
			if requiresSharing {
				Issue.record("Seed \(seed): \(repetitions.map(\.description).joined(separator: "\n"))")
			}
		}
		report.append("summary mock-sharing accepted=\(accepted) repeating=\(repeating.count) classes=\(repeating.reduce(0) { $0 + $1.repetitions.count }) functions=\(repeating.reduce(0) { $0 + $1.repetitions.reduce(0) { $0 + $1.functionNames.count } })")
	}

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
