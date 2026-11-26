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

struct SafeDIToolGraphFuzzerAPIVersionTests {
	@Test(.enabled(if: ProcessInfo.processInfo.environment["SAFEDI_API_VERSION_AGREEMENT_SEEDS"] != nil, "Set SAFEDI_API_VERSION_AGREEMENT_SEEDS to run"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func longRun_findsNoDisagreement_whenEnabledByEnvironment() async throws {
		let environment = ProcessInfo.processInfo.environment
		let seeds = Self.seeds(from: environment["SAFEDI_API_VERSION_AGREEMENT_SEEDS"] ?? "")
		let report = GraphFuzzerReport(path: environment["SAFEDI_API_VERSION_AGREEMENT_REPORT"])
		// `SAFEDI_API_VERSION_AGREEMENT_CORPUS` names the corpus by its release acceptance name: `base`, the default, or
		// `public-mock`.
		guard let corpus = GraphFuzzerReleaseAcceptanceCorpus(rawValue: environment["SAFEDI_API_VERSION_AGREEMENT_CORPUS"] ?? "base"), corpus != .seam else {
			Issue.record("SAFEDI_API_VERSION_AGREEMENT_CORPUS names no corpus the oracle runs: use base or public-mock.")
			return
		}
		report.append("api-version-agreement corpus=\(corpus.rawValue) seeds=\(seeds.count)")
		guard compileVerificationIsEnabled else {
			report.append("problem The agreement oracle compiles generated code. Unset SAFEDI_SKIP_COMPILE_CHECK.")
			Issue.record("The agreement oracle compiles generated code. Unset SAFEDI_SKIP_COMPILE_CHECK.")
			return
		}
		let start = Date()
		let verdicts = try await GraphFuzzerAPIVersionAgreement.verdicts(forSeeds: seeds, of: corpus)
		var classCounts = [GraphFuzzerReleaseAcceptanceClass: Int]()
		var unbuildableBuilderProbeCount = 0
		var unbuildableBuilderGraphCount = 0
		var mockProbeCount = 0
		for verdict in verdicts {
			classCounts[verdict.verdict.verdictClass, default: 0] += 1
			mockProbeCount += verdict.verdict.mockProbeCount
			unbuildableBuilderProbeCount += verdict.unbuildableBuilderProbeCount
			if verdict.unbuildableBuilderProbeCount > 0 {
				unbuildableBuilderGraphCount += 1
			}
			report.append("seed \(verdict.seed) \(verdict.verdict.classDescription) roots=\(verdict.verdict.rootProbeCount) mocks=\(verdict.verdict.mockProbeCount) d12=\(verdict.unbuildableBuilderProbeCount)")
			let pendingReason = GraphFuzzerAPIVersionAgreement.pendingReason(ofSeed: verdict.seed, in: corpus)
			if let pendingReason, verdict.verdict.verdictClass == .currentDoesNotCompile {
				report.append("    pending: \(pendingReason)")
				continue
			}
			if let pendingReason, !verdict.verdict.verdictClass.isBreak, verdict.verdict.verdictClass != .valuesNotCompared {
				report.append("stale \(verdict.seed) \(pendingReason)")
				Issue.record(Comment(rawValue: "Seed \(verdict.seed) is listed as pending (\(pendingReason)) but is class \(verdict.verdict.verdictClass.rawValue): remove it from its corpus's pending shapes in `GraphFuzzerAPIVersionAgreement`."))
				continue
			}
			guard verdict.verdict.verdictClass.isBreak || verdict.verdict.verdictClass == .valuesNotCompared else { continue }
			for detailLine in verdict.verdict.details.split(separator: "\n") {
				report.append("    \(detailLine)")
			}
			Issue.record(Comment(rawValue: "Seed \(verdict.seed): .v3Unstable class \(verdict.verdict.verdictClass.rawValue) against .v2\n\(verdict.verdict.details)"))
		}
		report.append("classes " + GraphFuzzerReleaseAcceptanceClass.allCases.sorted().map { "\($0.rawValue)=\(classCounts[$0, default: 0])" }.joined(separator: " "))
		report.append("probes mocks=\(mockProbeCount) d12=\(unbuildableBuilderProbeCount) d12-graphs=\(unbuildableBuilderGraphCount)")
		report.append("cpu wall=\(Int(Date().timeIntervalSince(start).rounded()))")
		report.append("completed \(verdicts.count)")
	}

	@Test(.disabled(if: !compileVerificationIsEnabled, "Compares compiled values"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func smokeSeeds_agreeAcrossAPIVersions_withTenGraphsAndTenUnbuildableBuilderProbesCompared() async throws {
		let verdicts = try await GraphFuzzerAPIVersionAgreement.verdicts(forSeeds: GraphFuzzerAPIVersionAgreement.smokeSeeds)
		for verdict in verdicts where verdict.verdict.verdictClass != .valuesAgree {
			Issue.record(Comment(rawValue: "Seed \(verdict.seed): .v3Unstable class \(verdict.verdict.verdictClass.rawValue) against .v2\n\(verdict.verdict.details)"))
		}
		#expect(verdicts.count(where: { $0.verdict.verdictClass == .valuesAgree }) >= 10)
		#expect(verdicts.map(\.unbuildableBuilderProbeCount).reduce(0, +) >= 10)
	}

	@Test(.disabled(if: !compileVerificationIsEnabled, "Compares compiled values"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func publicMockSmokeSeeds_agreeAcrossAPIVersions_withTenGraphsCompared() async throws {
		let verdicts = try await GraphFuzzerAPIVersionAgreement.verdicts(forSeeds: GraphFuzzerAPIVersionAgreement.publicMockSmokeSeeds, of: .publicMock)
		for verdict in verdicts where verdict.verdict.verdictClass != .valuesAgree {
			Issue.record(Comment(rawValue: "Seed \(verdict.seed): .v3Unstable class \(verdict.verdict.verdictClass.rawValue) against .v2\n\(verdict.verdict.details)"))
		}
		#expect(verdicts.count(where: { $0.verdict.verdictClass == .valuesAgree }) >= 10)
	}

	@Test
	func pendingShapes_listEachSeedOnceInIncreasingOrder_outsideTheSmokeSeeds() {
		for corpus in [GraphFuzzerReleaseAcceptanceCorpus.base, .publicMock] {
			let shapes = GraphFuzzerAPIVersionAgreement.pendingShapes(of: corpus)
			let seeds = shapes.flatMap(\.seeds)
			#expect(Set(seeds).count == seeds.count)
			for shape in shapes {
				#expect(shape.seeds == shape.seeds.sorted())
			}
			#expect(Set(seeds).isDisjoint(with: GraphFuzzerAPIVersionAgreement.smokeSeeds(of: corpus)))
		}
	}

	@Test
	func mockingEveryClass_addsGenerateMockToEachClass_whenNoHandWrittenMockIsBeside() {
		let fixture = GraphFuzzerFixture(seed: 7, swiftFileContent: [
			"""
			@Instantiable
			public final class S7_T0: Instantiable {
			}
			@Instantiable(isRoot: true)
			public final class S7_T1: Instantiable {
			}
			@Instantiable(generateMock: true)
			public final class S7_T2: Instantiable {
			}
			""",
			"""
			@Instantiable
			public final class S7_T3: Instantiable {
				public static func mock() -> S7_T3 { S7_T3() }
			}
			""",
		])
		#expect(fixture.mockingEveryClass.swiftFileContent == [
			"""
			@Instantiable(generateMock: true)
			public final class S7_T0: Instantiable {
			}
			@Instantiable(isRoot: true, generateMock: true)
			public final class S7_T1: Instantiable {
			}
			@Instantiable(generateMock: true)
			public final class S7_T2: Instantiable {
			}
			""",
			"""
			@Instantiable
			public final class S7_T3: Instantiable {
				public static func mock() -> S7_T3 { S7_T3() }
			}
			""",
		])
	}

	@Test
	func selectingAPIVersion_addsArgumentToDeclaredConfiguration_whenGraphDeclaresOne() {
		let fixture = GraphFuzzerFixture(seed: 7, swiftFileContent: [
			"@Instantiable\npublic final class S7_T0: Instantiable {}\n",
			"#SafeDIConfiguration(additionalMocksToGenerate: [S7_T0.self])\n",
		])
		#expect(fixture.selectingAPIVersion(.v3Unstable).swiftFileContent == [
			"@Instantiable\npublic final class S7_T0: Instantiable {}\n",
			"#SafeDIConfiguration(additionalMocksToGenerate: [S7_T0.self], apiVersion: .v3Unstable)\n",
		])
	}

	@Test
	func selectingAPIVersion_declaresConfigurationInFirstFile_whenGraphDeclaresNone() {
		let fixture = GraphFuzzerFixture(seed: 7, swiftFileContent: [
			"@Instantiable\npublic final class S7_T0: Instantiable {}\n",
			"@Instantiable\npublic final class S7_T1: Instantiable {}\n",
		])
		#expect(fixture.selectingAPIVersion(.v2).swiftFileContent == [
			"@Instantiable\npublic final class S7_T0: Instantiable {}\n\n#SafeDIConfiguration(apiVersion: .v2)\n",
			"@Instantiable\npublic final class S7_T1: Instantiable {}\n",
		])
	}

	@Test
	func selectingAPIVersion_selectsVersionInEveryModule_whenGraphIsSplitAcrossModules() {
		let fixture = GraphFuzzerFixture(seed: 7, swiftFileContent: [
			"// module: FuzzFeature\n@Instantiable\npublic final class S7_T0: Instantiable {}\n",
			"// module: FuzzFeature\n// file: SafeDIConfiguration.swift\n#SafeDIConfiguration(mockConditionalCompilation: nil)\n",
			"@Instantiable\npublic final class S7_T7: Instantiable {}\n",
			"// module: FuzzOther\n@Instantiable\npublic final class S7_T8: Instantiable {}\n",
			"// module: FuzzOther\n@Instantiable\npublic final class S7_T9: Instantiable {}\n",
		])
		#expect(fixture.selectingAPIVersion(.v3Unstable).swiftFileContent == [
			"// module: FuzzFeature\n@Instantiable\npublic final class S7_T0: Instantiable {}\n",
			"// module: FuzzFeature\n// file: SafeDIConfiguration.swift\n#SafeDIConfiguration(mockConditionalCompilation: nil, apiVersion: .v3Unstable)\n",
			"@Instantiable\npublic final class S7_T7: Instantiable {}\n\n#SafeDIConfiguration(apiVersion: .v3Unstable)\n",
			"// module: FuzzOther\n@Instantiable\npublic final class S7_T8: Instantiable {}\n\n#SafeDIConfiguration(apiVersion: .v3Unstable)\n",
			"// module: FuzzOther\n@Instantiable\npublic final class S7_T9: Instantiable {}\n",
		])
	}

	@Test
	func callingV3Mock_passesOwnDefaultInOverridesAndUnbuildableValueAsBuilder_whenProbePassesArgument() {
		let probes = [
			DifferentialValueProbe("S7_T0.mock(name: \"probe\")"),
			DifferentialValueProbe("S7_UnbuildableScreen.mock(unbuildableFilter: S7_UnbuildableFilter())"),
			DifferentialValueProbe("S7_T1.mock()"),
			DifferentialValueProbe("S7_Root0()"),
		].map(GraphFuzzerAPIVersionAgreement.callingV3Mock(_:))
		#expect(probes.map(\.name) == [
			"S7_T0.mock(name: \"probe\")",
			"S7_UnbuildableScreen.mock(unbuildableFilter: S7_UnbuildableFilter())",
			"S7_T1.mock()",
			"S7_Root0()",
		])
		#expect(probes.map(\.expression) == [
			"S7_T0.mock(safeDIOverrides: .init(name: \"probe\"))",
			"S7_UnbuildableScreen.mock(unbuildableFilter: { S7_UnbuildableFilter() })",
			"S7_T1.mock()",
			"S7_Root0()",
		])
		#expect(probes.map(\.knownRightExpression) == [
			"S7_T0.mock(name: \"probe\")",
			"S7_UnbuildableScreen.mock(unbuildableFilter: S7_UnbuildableFilter())",
			nil,
			nil,
		])
	}

	@Test
	func makingUnbuildableTypesInstantiable_declaresCountingInitializer_forEachUnbuildableType() {
		let fixture = GraphFuzzerFixture(seed: 7, swiftFileContent: [
			"""
			public final class S7_Unbuildable0: Sendable {
				let differentialValueCreationStamp = S7_Stamps.next()
			}
			public final class S7_Unbuildable1 {}
			""",
		])
		#expect(fixture.unbuildableTypeNames == ["S7_Unbuildable0", "S7_Unbuildable1"])
		#expect(fixture.makingUnbuildableTypesInstantiable?.swiftFileContent == [
			"""
			@Instantiable
			public final class S7_Unbuildable0: Instantiable, Sendable {
				public init() {
					S7_UnbuildableInitializations.count += 1
				}

				let differentialValueCreationStamp = S7_Stamps.next()
			}
			@Instantiable
			public final class S7_Unbuildable1: Instantiable {
				public init() {
					S7_UnbuildableInitializations.count += 1
				}
			}
			""",
			"// file: S7_UnbuildableInitializations.swift\n\npublic enum S7_UnbuildableInitializations {\n\tnonisolated(unsafe) public static var count = 0\n}\n",
		])
	}

	@Test
	func addingTwiceBuiltUnbuildableOwner_buildsFirstOwnerThroughInstantiator_whenGraphDrawsUnbuildableType() {
		let fixture = GraphFuzzerFixture(seed: 7, swiftFileContent: [
			"""
			@Instantiable(generateMock: true)
			public final class S7_T0: Instantiable {
				public init(t2: S7_Unbuildable0) {
					self.t2 = t2
				}

				@Instantiated let t2: S7_Unbuildable0
			}
			""",
			"public final class S7_Unbuildable0 {}\n",
		])
		#expect(fixture.addingTwiceBuiltUnbuildableOwner.swiftFileContent == fixture.swiftFileContent + [
			"""
			@Instantiable(generateMock: true)
			public final class S7_ZTwiceHost: Instantiable {
				let differentialValueCreationStamp = S7_CreationStamp.next()

				public init(zTwiceOwnerBuilder: Instantiator<S7_T0>) {
					self.zTwiceOwnerBuilder = zTwiceOwnerBuilder
				}

				@Instantiated let zTwiceOwnerBuilder: Instantiator<S7_T0>
			}

			""",
		])
	}

	@Test
	func addingTwiceBuiltUnbuildableOwner_leavesGraph_whenEveryOwnerForwards() {
		let fixture = GraphFuzzerFixture(seed: 7, swiftFileContent: [
			"""
			@Instantiable(generateMock: true)
			public final class S7_T0: Instantiable {
				public init(t1: Int, t2: S7_Unbuildable0) {
					self.t1 = t1
					self.t2 = t2
				}

				@Forwarded let t1: Int
				@Instantiated let t2: S7_Unbuildable0
			}
			""",
			"public final class S7_Unbuildable0 {}\n",
		])
		#expect(fixture.addingTwiceBuiltUnbuildableOwner == fixture)
	}

	@Test
	func makingUnbuildableTypesInstantiable_returnsNil_whenGraphDrawsNoUnbuildableType() {
		let fixture = GraphFuzzerFixture(seed: 7, swiftFileContent: ["@Instantiable\npublic final class S7_T0: Instantiable {}\n"])
		#expect(fixture.makingUnbuildableTypesInstantiable == nil)
	}

	@Test
	func unbuildableBuilderProbes_callEachMockTakingOnlyBuilders_withCountingBuilders() {
		let fixture = GraphFuzzerFixture(seed: 7, swiftFileContent: ["public final class S7_Unbuildable0 {}\n"])
		let probes = fixture.unbuildableBuilderProbes(v3GeneratedFiles: [
			"S7_T0+SafeDIMock.swift": """
			extension S7_T0 {
			    public static func mock(
			        t3: @escaping () -> S7_Unbuildable0,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> S7_T0 {
			""",
			"S7_T1+SafeDIMock.swift": """
			extension S7_T1 {
			    public static func mock(
			        t3: @escaping () -> S7_Unbuildable0,
			        value: Int
			    ) -> S7_T1 {
			""",
			"S7_T2+SafeDIMock.swift": """
			extension S7_T2 {
			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> S7_T2 {
			""",
		])
		#expect(probes == [
			DifferentialValueProbe(
				name: "S7_T0.mock(t3: builder)",
				expression: "{ () -> (Any, Int) in let calls = S7_UnbuildableBuilderCalls(); let value = S7_T0.mock(t3: { calls.count += 1; return S7_Unbuildable0() }); return (value, calls.count) }()",
				knownRightExpression: "{ () -> (Any, Int) in let before = S7_UnbuildableInitializations.count; let value = S7_T0.mock(); return (value, S7_UnbuildableInitializations.count - before) }()",
			),
		])
	}

	/// The seeds `specification` names: `a..<b`, or a comma-separated list.
	static func seeds(from specification: String) -> [UInt64] {
		let bounds = specification.components(separatedBy: "..<")
		if bounds.count == 2, let lower = UInt64(bounds[0]), let upper = UInt64(bounds[1]) {
			return Array(lower..<upper)
		}
		return specification.split(separator: ",").compactMap { UInt64($0.trimmingCharacters(in: .whitespaces)) }
	}

	@Test
	func seeds_readsRangeAndList_whenSpecificationNamesEither() {
		#expect(Self.seeds(from: "3..<6") == [3, 4, 5])
		#expect(Self.seeds(from: "4, 9,12") == [4, 9, 12])
	}
}
