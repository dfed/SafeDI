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
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// A root laid out from its per-type plan builds the values its tree built per path builds. Each graph is drawn in the
/// shape of an app's screens that open one another (`PlanValueGraph`), generated twice, once with every root the plan
/// can take laid out from its plan whatever its size (`RootTreeChoiceObservation.scopeGeneratorLimitOverride` of 0) and
/// once with every root kept on today's tree (an override of `.max`), and, where some root was laid
/// out from its plan, both outputs are compiled and run: every root is described by the differential value comparator,
/// which compares the instances each holds, which of them are one instance, and the order every class instance was
/// created in, since each stores the next value of a counter of its graph.
///
/// The suite compares the pinned graphs (`generate_buildsTodaysValues_whenPinnedGraphsAreLaidOutFromTheirPlan`); the long
/// run compares every graph drawn, only when `SAFEDI_PLAN_VALUE_GRAPHS` sets how many graphs with a root laid out from its
/// plan it compares. `SAFEDI_PLAN_VALUE_FIRST_SEED` sets the first seed drawn, and `SAFEDI_PLAN_VALUE_ROUND` how many are generated and
/// compared at a time. `SAFEDI_PLAN_VALUE_REPORT` names a file the report is written to after each round, and
/// `SAFEDI_PLAN_VALUE_ISOLATED_TRAVERSALS` how many wrappers a graph that spent the batch's traversals traverses when it is
/// compared again on its own.
struct SafeDIToolPerTypePlanValueTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = []
	}

	deinit {
		for fileToDelete in filesToDelete {
			try? FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	/// The graphs of `pinnedSeeds`, each laid out from its plan with the limit at 0, compared by value with today's tree in
	/// one batch at the batch's limits. `SAFEDI_PLAN_VALUE_PINNED` lists other seeds to compare in their place, which is how
	/// the list is picked again: every line of the report (`SAFEDI_PLAN_VALUE_REPORT`) names a seed, its shapes, whether
	/// its code differs from today's, and how it compared.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsTodaysValues_whenPinnedGraphsAreLaidOutFromTheirPlan() async throws {
		let environment = ProcessInfo.processInfo.environment
		let seeds = environment["SAFEDI_PLAN_VALUE_PINNED"].map { $0.split(separator: ",").compactMap { UInt64($0) } } ?? Self.pinnedSeeds
		let generated = await withTaskGroup(of: (UInt64, PlanValueGraph.Generated?).self) { group in
			for seed in seeds {
				group.addTask { await (seed, PlanValueGraph.generated(seed: seed)) }
			}
			var generatedBySeed = [UInt64: PlanValueGraph.Generated]()
			for await (seed, generated) in group {
				generatedBySeed[seed] = generated
			}
			return seeds.compactMap { generatedBySeed[$0] }
		}
		#expect(generated.map(\.graph.seed) == seeds, "every pinned graph is accepted")
		let notLaidOut = generated.filter(\.rootsLaidOutFromPlan.isEmpty).map(\.graph.seed)
		#expect(notLaidOut.isEmpty, "laid out from no root's plan: \(notLaidOut)")
		let graphs = generated.map { generated in
			DifferentialValueGraph(
				name: "seed \(generated.graph.seed)",
				feature: DifferentialValuePath(fixtureFiles: [generated.graph.fileName: generated.graph.source], generatedFiles: ["SafeDI.swift": generated.planCode]),
				knownRight: DifferentialValuePath(fixtureFiles: [generated.graph.fileName: generated.graph.source], generatedFiles: ["SafeDI.swift": generated.todaysCode]),
				probes: generated.graph.rootNames.map { DifferentialValueProbe("\($0)()") },
				samples: generated.graph.samples,
			)
		}
		guard let comparisons = try await DifferentialValueOracle.compare(graphs: graphs, filesToDelete: &filesToDelete) else { return }
		var lines = [String]()
		var failures = [String]()
		for (generated, comparison) in zip(generated, comparisons) {
			let outcome: String
			switch comparison.result {
			case let .success(result):
				outcome = result.differences.isEmpty ? "alike" : "differ: \(result.differences.map(\.description).joined(separator: "; "))"
				if !result.differences.isEmpty {
					failures.append("\(comparison.name): \(result.differences.map(\.description).joined(separator: "\n"))")
				}
			case let .failure(error):
				outcome = error.spentTraversals && error.path == nil ? "spent alike" : "failed"
				failures.append("\(comparison.name): \(error)")
			}
			lines.append("seed \(generated.graph.seed) \(generated.graph.shapes.joined(separator: ",")) code=\(generated.planCode == generated.todaysCode ? "same" : "differs") \(outcome)")
		}
		if let reportPath = environment["SAFEDI_PLAN_VALUE_REPORT"] {
			try lines.joined(separator: "\n").write(toFile: reportPath, atomically: true, encoding: .utf8)
		}
		// A graph whose plan writes today's code judges nothing, so each pinned graph is one whose code differs; when a change
		// makes one write today's code, or spend its traversals, pick the list again.
		let sameCode = generated.filter { $0.planCode == $0.todaysCode }.map(\.graph.seed)
		#expect(sameCode.isEmpty, "the plan writes today's code: \(sameCode)")
		#expect(failures.isEmpty, "\(failures.joined(separator: "\n\n"))")
	}

	/// The graphs `SAFEDI_PLAN_VALUE_SEEDS` lists, each compared alone with one probe per property of each root, at the
	/// batch's limits, so that a graph whose root spent its traversals on both paths is compared a property at a time.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsTodaysValuesInEachRootProperty_whenGraphSpentItsTraversals() async throws {
		let environment = ProcessInfo.processInfo.environment
		guard let seedList = environment["SAFEDI_PLAN_VALUE_SEEDS"] else { return }
		var lines = [String]()
		for seed in seedList.split(separator: ",").compactMap({ UInt64($0) }) {
			guard let generated = await PlanValueGraph.generated(seed: seed), !generated.rootsLaidOutFromPlan.isEmpty else {
				lines.append("seed \(seed): not laid out from the plan")
				continue
			}
			let probes = generated.graph.rootNames.flatMap { root in
				(generated.graph.rootPropertyLabels[root] ?? []).map { DifferentialValueProbe("\(root)().\($0)") }
			}
			let graph = DifferentialValueGraph(
				name: "seed \(seed)",
				feature: DifferentialValuePath(fixtureFiles: [generated.graph.fileName: generated.graph.source], generatedFiles: ["SafeDI.swift": generated.planCode]),
				knownRight: DifferentialValuePath(fixtureFiles: [generated.graph.fileName: generated.graph.source], generatedFiles: ["SafeDI.swift": generated.todaysCode]),
				probes: probes,
				samples: generated.graph.samples,
			)
			guard let comparison = try await DifferentialValueOracle.compare(graphs: [graph], filesToDelete: &filesToDelete)?.first else { return }
			for fileToDelete in filesToDelete {
				try? FileManager.default.removeItem(at: fileToDelete)
			}
			filesToDelete = []
			switch comparison.result {
			case let .success(result):
				lines.append("seed \(seed): \(probes.count) probes, \(result.differences.isEmpty ? "alike" : "differ: \(result.differences.map(\.description).joined(separator: "; "))")")
			case let .failure(error):
				lines.append("seed \(seed): \(probes.count) probes, \(error.spentTraversals && error.path == nil ? "spent alike: \(String(describing: error).prefix(300))" : "failed: \(error)")")
			}
			if let reportPath = environment["SAFEDI_PLAN_VALUE_REPORT"] {
				try lines.joined(separator: "\n").write(toFile: reportPath, atomically: true, encoding: .utf8)
			}
		}
		#expect(!lines.contains { $0.contains(": differ") || $0.contains(", failed") }, "\(lines.joined(separator: "\n"))")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsTodaysValuesInTodaysOrder_whenRootIsLaidOutFromItsPlan() async throws {
		let environment = ProcessInfo.processInfo.environment
		guard let graphsWanted = environment["SAFEDI_PLAN_VALUE_GRAPHS"].flatMap(Int.init) else { return }
		let firstSeed = environment["SAFEDI_PLAN_VALUE_FIRST_SEED"].flatMap(UInt64.init) ?? 0
		// Graphs are generated and compared a round at a time, so that the process holds one round's code at once.
		let roundSize = environment["SAFEDI_PLAN_VALUE_ROUND"].flatMap(Int.init) ?? 25
		let isolatedLimits = environment["SAFEDI_PLAN_VALUE_ISOLATED_TRAVERSALS"].flatMap(Int.init).map {
			DifferentialValueLimits(probeTimeLimitInSeconds: DifferentialValueLimits.isolatedFuzzerGraph.probeTimeLimitInSeconds, traversalsPerProbe: $0)
		} ?? .isolatedFuzzerGraph
		let traces = environment["SAFEDI_PLAN_VALUE_TRACE"] != nil
		var seed = firstSeed
		var drawn = 0
		var accepted = 0
		var laidOutCount = 0
		var differingInCodeLines = [String]()
		var comparedCount = 0
		var failures = [String]()
		// Graphs both paths describe alike down to the larger limit, where both spent their traversals at one node.
		var spentAlike = [String]()
		while laidOutCount < graphsWanted {
			var laidOut = [PlanValueGraph.Generated]()
			while laidOut.count < min(roundSize, graphsWanted - laidOutCount) {
				// Each batch of seeds is generated side by side; `generate` runs its own work in parallel too.
				let seeds = (0..<UInt64(16)).map { seed + $0 }
				let generated = await withTaskGroup(of: PlanValueGraph.Generated?.self) { group in
					for seed in seeds {
						group.addTask {
							// Names each seed as it starts and ends, so a graph that never ends is found.
							if traces {
								FileHandle.standardError.write(Data("plan-values start \(seed)\n".utf8))
							}
							let generated = await PlanValueGraph.generated(seed: seed)
							if traces {
								FileHandle.standardError.write(Data("plan-values end \(seed)\n".utf8))
							}
							return generated
						}
					}
					var generated = [PlanValueGraph.Generated?]()
					for await result in group {
						generated.append(result)
					}
					return generated.compactMap(\.self).sorted { $0.graph.seed < $1.graph.seed }
				}
				let wanted = min(roundSize, graphsWanted - laidOutCount) - laidOut.count
				let laidOutOfBatch = generated.filter { !$0.rootsLaidOutFromPlan.isEmpty }
				if laidOutOfBatch.count > wanted {
					// Stop the round at the last graph it needs, so the next round's first seed follows it.
					let lastSeed = laidOutOfBatch[wanted - 1].graph.seed
					drawn += Int(lastSeed + 1 - seed)
					accepted += generated.filter { $0.graph.seed <= lastSeed }.count
					laidOut += laidOutOfBatch.prefix(wanted)
					seed = lastSeed + 1
				} else {
					drawn += seeds.count
					accepted += generated.count
					laidOut += laidOutOfBatch
					seed += 16
				}
			}
			laidOutCount += laidOut.count
			let differingInCode = laidOut.filter { $0.planCode != $0.todaysCode }
			differingInCodeLines += differingInCode.map { "differs \($0.graph.seed) roots=\($0.rootsLaidOutFromPlan.sorted().joined(separator: ",")) shapes=\($0.graph.shapes.joined(separator: ","))" }

			// Code that is the same both ways builds the same values: only the graphs whose code differs are compiled.
			let graphs = differingInCode.map { generated in
				DifferentialValueGraph(
					name: "seed \(generated.graph.seed)",
					feature: DifferentialValuePath(fixtureFiles: [generated.graph.fileName: generated.graph.source], generatedFiles: ["SafeDI.swift": generated.planCode]),
					knownRight: DifferentialValuePath(fixtureFiles: [generated.graph.fileName: generated.graph.source], generatedFiles: ["SafeDI.swift": generated.todaysCode]),
					probes: generated.graph.rootNames.map { DifferentialValueProbe("\($0)()") },
					samples: generated.graph.samples,
				)
			}
			laidOut = []
			var comparisons = [DifferentialValueGraphComparison]()
			if traces {
				// One graph at a time, named as it starts and ends, so a comparison that never ends is found.
				for graph in graphs {
					FileHandle.standardError.write(Data("plan-values compare start \(graph.name)\n".utf8))
					guard let graphComparisons = try await DifferentialValueOracle.compare(graphs: [graph], filesToDelete: &filesToDelete) else { return }
					comparisons += graphComparisons
					FileHandle.standardError.write(Data("plan-values compare end \(graph.name)\n".utf8))
				}
			} else {
				guard let batchComparisons = try await DifferentialValueOracle.compare(graphs: graphs, filesToDelete: &filesToDelete) else { return }
				comparisons = batchComparisons
			}
			// A graph whose probe spent its traversals is compared again on its own terms, as the graph fuzzer does.
			let spentGraphs = zip(graphs, comparisons).compactMap { graph, comparison -> DifferentialValueGraph? in
				guard case let .failure(error) = comparison.result, error.spentTraversals else { return nil }
				return graph
			}
			// One at a time, since two descriptions at the larger limit can hold more memory than the machine has.
			var spentComparisonsByName = [String: DifferentialValueGraphComparison]()
			for spentGraph in spentGraphs {
				if traces {
					FileHandle.standardError.write(Data("plan-values isolated start \(spentGraph.name)\n".utf8))
				}
				for comparison in try await DifferentialValueOracle.compare(graphs: [spentGraph], limits: isolatedLimits, filesToDelete: &filesToDelete) ?? [] {
					spentComparisonsByName[comparison.name] = comparison
				}
			}
			for comparison in comparisons.map({ spentComparisonsByName[$0.name] ?? $0 }) {
				switch comparison.result {
				case let .success(result):
					comparedCount += 1
					if !result.differences.isEmpty {
						failures.append("\(comparison.name): \(result.differences.map(\.description).joined(separator: "\n"))")
					}
				case let .failure(error):
					if error.spentTraversals, error.path == nil {
						spentAlike.append(comparison.name)
					} else {
						comparedCount += 1
						failures.append("\(comparison.name): \(error)")
					}
				}
			}
			for fileToDelete in filesToDelete {
				try? FileManager.default.removeItem(at: fileToDelete)
			}
			filesToDelete = []
			let report = "plan-values drawn=\(drawn) accepted=\(accepted) laid-out=\(laidOutCount) differ-in-code=\(differingInCodeLines.count) compared=\(comparedCount) spent-alike=\(spentAlike.count) failures=\(failures.count) seeds=\(firstSeed)..<\(seed)"
			print(report)
			if let reportPath = environment["SAFEDI_PLAN_VALUE_REPORT"] {
				try ([report] + differingInCodeLines + spentAlike.map { "spent-alike \($0)" } + failures).joined(separator: "\n").write(toFile: reportPath, atomically: true, encoding: .utf8)
			}
		}
		#expect(laidOutCount == graphsWanted)
		#expect(failures.isEmpty, "\(failures.joined(separator: "\n\n"))")
	}

	/// A `LazilyInstantiated` declaration's instance is built when it is first read, wherever its reader is: beneath the
	/// declaring type itself (the direct path), and beneath a type on the declaring type's cycle, whose function takes
	/// the wrapper as a parameter. The fixture counts each `Leaf` built, and each probe lists the count after every
	/// step, on the root laid out from its plan and on today's tree.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsLazilyInstantiatedInstanceAtFirstRead_whenReaderIsBeneathDeclaringTypeOrAcrossCall() async throws {
		let source = """
		@Instantiable(isRoot: true)
		public final class PlanLazyCountRoot: Instantiable {
		    public init(s0Builder: Instantiator<PlanLazyCountS0>) {
		        self.s0Builder = s0Builder
		    }

		    @Instantiated public let s0Builder: Instantiator<PlanLazyCountS0>
		}

		@Instantiable
		public final class PlanLazyCountS0: Instantiable {
		    public init(leaf: LazilyInstantiated<PlanLazyCountLeaf>, readerBuilder: Instantiator<PlanLazyCountReader>, s1Builder: Instantiator<PlanLazyCountS1>) {
		        self.leaf = leaf
		        self.readerBuilder = readerBuilder
		        self.s1Builder = s1Builder
		    }

		    @Instantiated public let leaf: LazilyInstantiated<PlanLazyCountLeaf>
		    @Instantiated public let readerBuilder: Instantiator<PlanLazyCountReader>
		    @Instantiated public let s1Builder: Instantiator<PlanLazyCountS1>
		}

		@Instantiable
		public final class PlanLazyCountS1: Instantiable {
		    public init(readerBuilder: Instantiator<PlanLazyCountReader>, s0Builder: Instantiator<PlanLazyCountS0>) {
		        self.readerBuilder = readerBuilder
		        self.s0Builder = s0Builder
		    }

		    @Instantiated public let readerBuilder: Instantiator<PlanLazyCountReader>
		    @Instantiated public let s0Builder: Instantiator<PlanLazyCountS0>
		}

		@Instantiable
		public final class PlanLazyCountReader: Instantiable {
		    public init(leaf: PlanLazyCountLeaf) {
		        self.leaf = leaf
		    }

		    @Received public let leaf: PlanLazyCountLeaf
		}

		@Instantiable
		public final class PlanLazyCountLeaf: Instantiable {
		    public init() {
		        PlanLazyCount.leavesBuilt += 1
		    }
		}

		public enum PlanLazyCount {
		    nonisolated(unsafe) public static var leavesBuilt = 0

		    /// The leaves built after the root, after its screen, and after each of two readers beneath that screen.
		    public static func leavesBuiltOnDirectPath() -> [Int] {
		        leavesBuilt = 0
		        let root = PlanLazyCountRoot()
		        var counts = [leavesBuilt]
		        let s0 = root.s0Builder.instantiate()
		        counts.append(leavesBuilt)
		        let firstReader = s0.readerBuilder.instantiate()
		        counts.append(leavesBuilt)
		        let secondReader = s0.readerBuilder.instantiate()
		        counts.append(leavesBuilt)
		        counts.append(firstReader.leaf === secondReader.leaf ? 1 : 0)
		        return counts
		    }

		    /// The leaves built after the root, after its screen, after the screen that one opens, after a reader beneath
		    /// that screen, after the first screen opened again from there, and after a reader beneath it.
		    public static func leavesBuiltThroughParameter() -> [Int] {
		        leavesBuilt = 0
		        let root = PlanLazyCountRoot()
		        var counts = [leavesBuilt]
		        let s0 = root.s0Builder.instantiate()
		        counts.append(leavesBuilt)
		        let s1 = s0.s1Builder.instantiate()
		        counts.append(leavesBuilt)
		        let reader = s1.readerBuilder.instantiate()
		        counts.append(leavesBuilt)
		        let innerS0 = s1.s0Builder.instantiate()
		        counts.append(leavesBuilt)
		        let innerReader = innerS0.readerBuilder.instantiate()
		        counts.append(leavesBuilt)
		        counts.append(reader.leaf === s0.leaf.instance ? 1 : 0)
		        counts.append(innerReader.leaf === reader.leaf ? 1 : 0)
		        return counts
		    }
		}

		"""
		let fileName = "PlanLazyCount.swift"
		let generated = try #require(await PlanValueGraph.generatedCode(ofSource: source, fileName: fileName))
		#expect(generated.rootsLaidOutFromPlan == ["PlanLazyCountRoot"])
		let graph = DifferentialValueGraph(
			name: "lazy count",
			feature: DifferentialValuePath(fixtureFiles: [fileName: source], generatedFiles: ["SafeDI.swift": generated.planCode]),
			knownRight: DifferentialValuePath(fixtureFiles: [fileName: source], generatedFiles: ["SafeDI.swift": generated.todaysCode]),
			probes: [
				DifferentialValueProbe("PlanLazyCount.leavesBuiltOnDirectPath()"),
				DifferentialValueProbe("PlanLazyCount.leavesBuiltThroughParameter()"),
			],
		)
		guard let comparison = try await DifferentialValueOracle.compare(graphs: [graph], filesToDelete: &filesToDelete)?.first else { return }
		let result = try comparison.result.get()
		#expect(result.differences.map(\.description) == [])
		// Nothing is built until a reader is: the root, its screen and the screen that one opens build no leaf. Each
		// screen's readers share its one leaf (the last entries are 1 where two readers hold one instance), and the first
		// screen opened again declares a leaf of its own.
		#expect(result.featureDescription == """
		probe PlanLazyCount.leavesBuiltOnDirectPath()
		Array<Int>
		  0: Int 0
		  1: Int 0
		  2: Int 1
		  3: Int 1
		  4: Int 1
		probe PlanLazyCount.leavesBuiltThroughParameter()
		Array<Int>
		  0: Int 0
		  1: Int 0
		  2: Int 0
		  3: Int 1
		  4: Int 1
		  5: Int 2
		  6: Int 1
		  7: Int 0

		""")
	}

	/// A `LazilyInstantiated` declaration's instance is built once, at its first read, where the wrapper is passed
	/// through two functions of a cycle before its reader, and a `LazilyInstantiated` closes that cycle.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsLazilyInstantiatedInstanceOnceAtFirstRead_whenWrapperPassesThroughTwoFunctionsOfCycleLazyWrapperCloses() async throws {
		let source = """
		@Instantiable(isRoot: true)
		public final class PlanLazyRingRoot: Instantiable {
		    public init(s0Builder: Instantiator<PlanLazyRingS0>) {
		        self.s0Builder = s0Builder
		    }

		    @Instantiated public let s0Builder: Instantiator<PlanLazyRingS0>
		}

		@Instantiable
		public final class PlanLazyRingS0: Instantiable {
		    public init(leaf: LazilyInstantiated<PlanLazyRingLeaf>, s1Builder: Instantiator<PlanLazyRingS1>) {
		        self.leaf = leaf
		        self.s1Builder = s1Builder
		    }

		    @Instantiated public let leaf: LazilyInstantiated<PlanLazyRingLeaf>
		    @Instantiated public let s1Builder: Instantiator<PlanLazyRingS1>
		}

		@Instantiable
		public final class PlanLazyRingS1: Instantiable {
		    public init(s2Builder: Instantiator<PlanLazyRingS2>) {
		        self.s2Builder = s2Builder
		    }

		    @Instantiated public let s2Builder: Instantiator<PlanLazyRingS2>
		}

		@Instantiable
		public final class PlanLazyRingS2: Instantiable {
		    public init(readerBuilder: Instantiator<PlanLazyRingReader>, s0: LazilyInstantiated<PlanLazyRingS0>) {
		        self.readerBuilder = readerBuilder
		        self.s0 = s0
		    }

		    @Instantiated public let readerBuilder: Instantiator<PlanLazyRingReader>
		    @Instantiated public let s0: LazilyInstantiated<PlanLazyRingS0>
		}

		@Instantiable
		public final class PlanLazyRingReader: Instantiable {
		    public init(leaf: PlanLazyRingLeaf) {
		        self.leaf = leaf
		    }

		    @Received public let leaf: PlanLazyRingLeaf
		}

		@Instantiable
		public final class PlanLazyRingLeaf: Instantiable {
		    public init() {
		        PlanLazyRing.leavesBuilt += 1
		    }
		}

		public enum PlanLazyRing {
		    nonisolated(unsafe) public static var leavesBuilt = 0

		    /// The leaves built after the root, after each of the three screens of the ring, after each of two readers
		    /// beneath the last, and after the first screen is read from the wrapper that closes the ring; then whether
		    /// the two readers and the first screen hold one leaf, and whether the screen read from the closing wrapper
		    /// holds another.
		    public static func leavesBuiltAroundRing() -> [Int] {
		        leavesBuilt = 0
		        let root = PlanLazyRingRoot()
		        var counts = [leavesBuilt]
		        let s0 = root.s0Builder.instantiate()
		        counts.append(leavesBuilt)
		        let s1 = s0.s1Builder.instantiate()
		        counts.append(leavesBuilt)
		        let s2 = s1.s2Builder.instantiate()
		        counts.append(leavesBuilt)
		        let firstReader = s2.readerBuilder.instantiate()
		        counts.append(leavesBuilt)
		        let secondReader = s2.readerBuilder.instantiate()
		        counts.append(leavesBuilt)
		        let closingS0 = s2.s0.instance
		        counts.append(leavesBuilt)
		        counts.append(firstReader.leaf === secondReader.leaf && firstReader.leaf === s0.leaf.instance ? 1 : 0)
		        counts.append(leavesBuilt)
		        counts.append(closingS0.leaf.instance === s0.leaf.instance ? 1 : 0)
		        counts.append(leavesBuilt)
		        return counts
		    }
		}

		"""
		let fileName = "PlanLazyRing.swift"
		let generated = try #require(await PlanValueGraph.generatedCode(ofSource: source, fileName: fileName))
		#expect(generated.rootsLaidOutFromPlan == ["PlanLazyRingRoot"])
		let graph = DifferentialValueGraph(
			name: "lazy ring",
			feature: DifferentialValuePath(fixtureFiles: [fileName: source], generatedFiles: ["SafeDI.swift": generated.planCode]),
			knownRight: DifferentialValuePath(fixtureFiles: [fileName: source], generatedFiles: ["SafeDI.swift": generated.todaysCode]),
			probes: [DifferentialValueProbe("PlanLazyRing.leavesBuiltAroundRing()")],
		)
		guard let comparison = try await DifferentialValueOracle.compare(graphs: [graph], filesToDelete: &filesToDelete)?.first else { return }
		let result = try comparison.result.get()
		#expect(result.differences.map(\.description) == [])
		// No screen builds the leaf; the first reader does, the second shares it with the first screen, and reading the
		// screen the closing wrapper holds builds none until that screen's own leaf is read, which is another instance.
		#expect(result.featureDescription == """
		probe PlanLazyRing.leavesBuiltAroundRing()
		Array<Int>
		  0: Int 0
		  1: Int 0
		  2: Int 0
		  3: Int 0
		  4: Int 1
		  5: Int 1
		  6: Int 1
		  7: Int 1
		  8: Int 1
		  9: Int 0
		  10: Int 2

		""")
	}

	// MARK: Private

	/// Every graph of seeds 0..<23,705 (15,000 laid out from their plans by the long run) whose plan writes other code than
	/// today's tree and whose probes stay within the batch's limits: 31 graphs, which draw each of `PlanValueGraph.shapes`
	/// but `renames`, `escapingName`, `erases` and `receivesBuilder` at least four times. Of seeds 0..<3,483, two graphs that draw a rename write other code than today's:
	/// 1,981, pinned, and 246, which spends the batch's traversals alike on both paths. The other 214 whose code differs
	/// spend them too, and are left to the long run. Of seeds 0..<1,200, the 12 accepted graphs that forward a closure
	/// `@escaping` are all laid out from their plans with today's code, so none is pinned; 51 graphs that open a screen
	/// erased are accepted and 50 laid out from their plans, and two write other code than today's, 190 and 211, both
	/// pinned. Of seeds 0..<1,500, 65 graphs that receive a builder are accepted; the three whose code differs, 414, 692
	/// and 1,423, spend the batch's traversals alike on both paths.
	private static let pinnedSeeds: [UInt64] = [
		190, 211, 335, 576, 1_100, 1_311, 1_321, 1_981, 2_394, 3_074, 3_930, 4_235, 4_574, 4_648, 6_607,
		6_798, 8_112, 8_776, 9_172, 9_746, 10_419, 10_499, 11_225, 11_856, 13_584, 14_751, 15_247,
		15_663, 17_599, 17_996, 18_272, 20_050, 20_842, 22_429,
	]

	private var filesToDelete: [URL]
}

// MARK: - PlanValueGraph

/// A graph of an app's screens that open one another through instantiators: one to three services, each receiving
/// some of those before it, up to three models, two to seven screens, each receiving some services and models, declaring
/// some models, forwarding an `Int` about a third of the time and opening one to three screens, and one or two roots
/// that build every service and open one or two screens, directly or through a type in between. A few graphs draw a
/// lazily instantiated wrapper, a rename, a typealiased closure forwarded and received `@escaping` or a screen opened
/// through an erased instantiator of a concrete existential or a builder received, which a plan lays out, a `Sendable`
/// wrapper, which a plan lays out where no body is called both inside and outside a `@Sendable` function and whose graph
/// declares its classes `Sendable`, or a value received only if available, which keeps its root on today's tree. The shape is the one the per-type plan's review drew its graphs from; its types are prefixed by
/// the seed, so that a batch compiles many graphs side by side, and every class stores two counters' values: the
/// creation stamp the comparator reads (`DifferentialValueCreationStamp`) and `creationOrder`, which it describes.
struct PlanValueGraph {
	let seed: UInt64
	let source: String
	let rootNames: [String]
	/// Each root's labels, in declaration order, which a probe of one property reads.
	let rootPropertyLabels: [String: [String]]
	let forwardingTypeNames: [String]
	/// The types of `forwardingTypeNames` that forward a typealiased closure, declared `@escaping`, in place of an `Int`.
	let closureForwardingTypeNames: Set<String>
	/// What the graph draws of the shapes a plan lays out, which `pinnedSeeds` are spread over: `fewScreens`,
	/// `someScreens` or `manyScreens` (two or three, four or five, six or seven), `forwards`, `opensItself` (a screen
	/// opens itself), `declaresModel`, `receivesModel` (a screen receives a model it does not declare), `typeBetween`
	/// (a root opens its screens through a type in between), `screenByValue` (a root holds a screen by value),
	/// `twoRoots`, `renames` (a screen renames a service) `escapingName` (a screen forwards a typealiased closure
	/// `@escaping`) `erases` (a screen opens another through an erased instantiator)
	/// `receivesBuilder` (a screen receives a builder the root declares) and `sendableWrapper` (a screen opens another
	/// through a `SendableInstantiator`).
	let shapes: [String]

	/// A value of each forwarding type's forwarded properties, for the comparator to build its screens with.
	var samples: [DifferentialValueSample] {
		forwardingTypeNames.map { DifferentialValueSample(type: "\($0).ForwardedProperties", expression: closureForwardingTypeNames.contains($0) ? "{ _ in }" : "7") }
	}

	var fileName: String {
		"PlanValue\(seed).swift"
	}

	/// The graph's code generated as the driver chooses and with every root kept on today's tree.
	struct Generated {
		let graph: PlanValueGraph
		let planCode: String
		let todaysCode: String
		let rootsLaidOutFromPlan: Set<String>
	}

	/// The graph of `seed` generated both ways, or `nil` where the tool rejects it.
	static func generated(seed: UInt64) async -> Generated? {
		let graph = PlanValueGraph(seed: seed)
		guard let code = await generatedCode(ofSource: graph.source, fileName: graph.fileName) else { return nil }
		return Generated(graph: graph, planCode: code.planCode, todaysCode: code.todaysCode, rootsLaidOutFromPlan: code.rootsLaidOutFromPlan)
	}

	/// The code of one fixture file generated as the driver chooses with the limit at 0 and with every root kept on
	/// today's tree, and the roots the first laid out from their plans, or `nil` where the tool rejects the fixture.
	static func generatedCode(ofSource source: String, fileName: String) async -> (planCode: String, todaysCode: String, rootsLaidOutFromPlan: Set<String>)? {
		let directory = TestTemporaryDirectory.uniquePath(prefix: "plan-value-\(fileName)-")
		defer { try? FileManager.default.removeItem(at: directory) }
		do {
			try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
			let fixture = directory.appendingPathComponent(fileName)
			try source.write(to: fixture, atomically: true, encoding: .utf8)
			let csv = directory.appendingPathComponent("sources.csv")
			try fixture.path.write(to: csv, atomically: true, encoding: .utf8)
			let (stream, continuation) = AsyncStream.makeStream(of: (String, RootTreeChoiceObservation.PerPathReason?).self)
			let planCode = try await RootTreeChoiceObservation.$observer.withValue(TaskLocalFunction { root, perPathReason in
				continuation.yield((root, perPathReason))
			}) {
				try await RootTreeChoiceObservation.$scopeGeneratorLimitOverride.withValue(0) {
					try await generate(csv: csv, output: directory.appendingPathComponent("plan.swift"))
				}
			}
			continuation.finish()
			var rootsLaidOutFromPlan = Set<String>()
			for await (root, perPathReason) in stream where perPathReason == nil {
				rootsLaidOutFromPlan.insert(root)
			}
			let todaysCode = try await RootTreeChoiceObservation.$scopeGeneratorLimitOverride.withValue(.max) {
				try await generate(csv: csv, output: directory.appendingPathComponent("today.swift"))
			}
			return (planCode, todaysCode, rootsLaidOutFromPlan)
		} catch {
			return nil
		}
	}

	private static func generate(csv: URL, output: URL) async throws -> String {
		let tool = try Generate.parse([csv.path, "--combined-output", output.path, "--active-compilation-conditions", "DEBUG"])
		_ = try await tool.generate()
		return try String(contentsOf: output, encoding: .utf8)
	}

	init(seed: UInt64) {
		self.seed = seed
		var random = SplitMix64(seed: seed)
		let prefix = "PV\(seed)_"
		func name(_ type: String) -> String {
			prefix + type
		}
		func lowered(_ type: String) -> String {
			type.prefix(1).lowercased() + type.dropFirst()
		}
		let stampCounter = name("Stamp")
		let orderCounter = name("Order")
		var declarations = [String]()
		func declare(_ typeName: String, _ properties: [Property], attribute: String = "@Instantiable") {
			var lines = [attribute, "public final class \(name(typeName)): Instantiable {"]
			lines.append("    public init(" + properties.map { "\($0.label): \($0.initializerType)" }.joined(separator: ", ") + ") {")
			lines += properties.map { "        self.\($0.label) = \($0.label)" }
			lines.append("    }")
			lines.append("")
			lines += properties.map { "    \($0.attribute) public let \($0.label): \($0.type)" }
			lines.append("    public let creationOrder = \(orderCounter).next()")
			lines.append("    " + DifferentialValueCreationStamp.property(counterNamed: stampCounter))
			lines.append("}")
			declarations.append(lines.joined(separator: "\n"))
		}

		let serviceCount = random.int(in: 1...3)
		let screenCount = random.int(in: 2...7)
		let services = (0..<serviceCount).map { "Service\($0)" }
		for (index, service) in services.enumerated() {
			let properties = (0..<index).compactMap { other in random.chance(0.4) ? Property.received("service\(other)", name("Service\(other)")) : nil }
			declare(service, properties)
		}
		let models = (0..<random.int(in: 0...3)).map { "Model\($0)" }
		for model in models {
			let properties = (0..<serviceCount).compactMap { other in random.chance(0.4) ? Property.received("service\(other)", name("Service\(other)")) : nil }
			declare(model, properties)
		}
		let forwards = (0..<screenCount).map { _ in random.chance(0.35) }
		let edges = (0..<screenCount).map { _ in random.sample(from: Array(0..<screenCount), count: min(screenCount, random.int(in: 1...3))) }
		let odd = random.unit()
		let declaredModels = (0..<screenCount).map { _ in models.filter { _ in random.chance(0.3) } }
		// A few graphs forward a typealiased closure in place of the `Int`, which each initializer declares `@escaping`,
		// and have screens receive it.
		let drawsClosure = odd > 0.70 && odd < 0.76
		let forwardsClosure = (0..<screenCount).map { screen in drawsClosure && forwards[screen] && random.chance(0.6) }
		let closureForwarders = (0..<screenCount).filter { forwardsClosure[$0] }
		let onTap = name("OnTap")
		var screens = [(String, [Property])]()
		var receivesModel = false
		var renames = false
		var erases = false
		// A few graphs have screens receive a builder of a leaf that the root declares.
		let drawsReceivedBuilder = odd > 0.86 && odd < 0.93
		var receivesBuilder = false
		var holdsSendableWrapper = false
		for screen in 0..<screenCount {
			var properties = [Property]()
			if forwardsClosure[screen] {
				properties.append(Property(attribute: "@Forwarded", label: "onTap\(screen)", type: onTap, initializerType: "@escaping \(onTap)"))
			} else if forwards[screen] {
				properties.append(Property(attribute: "@Forwarded", label: "id\(screen)", type: "Int"))
			}
			if let forwarder = closureForwarders.first, forwarder != screen, random.chance(0.4) {
				properties.append(Property(attribute: "@Received", label: "onTap\(forwarder)", type: onTap, initializerType: "@escaping \(onTap)"))
			}
			properties += (0..<serviceCount).compactMap { other in random.chance(0.6) ? Property.received("service\(other)", name("Service\(other)")) : nil }
			properties += declaredModels[screen].map { Property(attribute: "@Instantiated", label: lowered($0), type: name($0)) }
			for model in models where !declaredModels[screen].contains(model) && random.chance(0.08) {
				properties.append(.received(lowered(model), name(model)))
				receivesModel = true
			}
			for edge in edges[screen] {
				var wrapper = "Instantiator"
				if odd < 0.08, random.chance(0.3) {
					wrapper = "SendableInstantiator"
					holdsSendableWrapper = true
				}
				if odd > 0.94, random.chance(0.2) {
					wrapper = "LazilyInstantiated"
				}
				if odd > 0.77, odd < 0.83, random.chance(0.4) {
					// A few graphs open a screen through an erased instantiator of a concrete existential.
					let arguments = forwardsClosure[edge] ? onTap : forwards[edge] ? "Int" : "()"
					properties.append(Property(attribute: "@Instantiated(fulfilledByType: \"\(name("S\(edge)"))\", erasedToConcreteExistential: true)", label: "s\(edge)Builder", type: "ErasedInstantiator<\(arguments), \(name("AnyScreen"))>"))
					erases = true
				} else {
					properties.append(Property(attribute: "@Instantiated", label: wrapper == "LazilyInstantiated" ? "s\(edge)Lazy" : "s\(edge)Builder", type: "\(wrapper)<\(name("S\(edge)"))>"))
				}
			}
			if drawsReceivedBuilder, random.chance(0.3) {
				properties.append(.received("leafBuilder", "Instantiator<\(name("Leaf"))>"))
				receivesBuilder = true
			}
			if odd > 0.4, odd < 0.5, random.chance(0.3) {
				properties.append(Property(attribute: "@Received(onlyIfAvailable: true)", label: "maybe", type: name("Maybe") + "?"))
			}
			if odd > 0.5, odd < 0.56, random.chance(0.3) {
				properties.append(Property(attribute: "@Received(fulfilledByDependencyNamed: \"service0\", ofType: \(name("Service0")).self)", label: "renamed", type: name("Service0")))
				renames = true
			}
			random.shuffle(&properties)
			// One dependency per label.
			var labels = Set<String>()
			properties = properties.filter { labels.insert($0.label).inserted }
			screens.append(("S\(screen)", properties))
		}
		for (screen, properties) in screens {
			declare(screen, properties)
		}
		if odd > 0.4, odd < 0.5 {
			declare("Maybe", [])
		}
		if drawsReceivedBuilder {
			declare("Leaf", [])
		}
		if erases {
			declarations.append("public final class \(name("AnyScreen")) {\n    public init(_ screen: AnyObject) { self.screen = screen }\n    public let screen: AnyObject\n}")
		}
		if !closureForwarders.isEmpty {
			declarations.append("public typealias \(onTap) = (Int) -> Void")
		}
		var rootNames = [String]()
		var rootPropertyLabels = [String: [String]]()
		var buildsAnyTypeBetween = false
		var holdsScreenByValue = false
		for root in 0..<(random.chance(0.85) ? 1 : 2) {
			var properties = (0..<serviceCount).map { Property(attribute: "@Instantiated", label: "service\($0)", type: name("Service\($0)")) }
			let tops = random.sample(from: Array(0..<screenCount), count: min(screenCount, random.int(in: 1...2)))
			let buildsTypeBetween = random.chance(0.25)
			if odd > 0.4, odd < 0.5, random.chance(0.5) {
				properties.append(Property(attribute: "@Instantiated", label: "maybe", type: name("Maybe")))
			}
			if drawsReceivedBuilder {
				properties.append(Property(attribute: "@Instantiated", label: "leafBuilder", type: "Instantiator<\(name("Leaf"))>"))
			}
			for model in models where random.chance(0.3) {
				properties.append(Property(attribute: "@Instantiated", label: lowered(model), type: name(model)))
			}
			if buildsTypeBetween {
				buildsAnyTypeBetween = true
				properties.append(Property(attribute: "@Instantiated", label: "mid\(root)", type: name("Mid\(root)")))
				var midProperties = (0..<serviceCount).compactMap { other in random.chance(0.5) ? Property.received("service\(other)", name("Service\(other)")) : nil }
				midProperties += tops.map { Property(attribute: "@Instantiated", label: "s\($0)Builder", type: "Instantiator<\(name("S\($0)"))>") }
				if let model = models.first, random.chance(0.5) {
					midProperties.append(Property(attribute: "@Instantiated", label: lowered(model), type: name(model)))
				}
				declare("Mid\(root)", midProperties)
			} else {
				for top in tops {
					if forwards[top] || random.chance(0.6) {
						properties.append(Property(attribute: "@Instantiated", label: "s\(top)Builder", type: "Instantiator<\(name("S\(top)"))>"))
					} else {
						properties.append(Property(attribute: "@Instantiated", label: "s\(top)", type: name("S\(top)")))
						holdsScreenByValue = true
					}
				}
			}
			random.shuffle(&properties)
			declare("Root\(root)", properties, attribute: "@Instantiable(isRoot: true)")
			rootNames.append(name("Root\(root)"))
			rootPropertyLabels[name("Root\(root)")] = properties.map(\.label)
		}
		if holdsSendableWrapper {
			// A `Sendable` wrapper's builder function is `@Sendable` and captures the services, models and screens declared
			// outside it, which an app declares `Sendable`; the graph's classes are, unchecked, since a screen stores
			// instantiators. Declared after every draw, so a graph's other shapes draw as before.
			declarations = declarations.map { $0.replacingOccurrences(of: ": Instantiable {", with: ": Instantiable, @unchecked Sendable {") }
		}
		random.shuffle(&declarations)
		declarations.append(DifferentialValueCreationStamp.counterDeclaration(named: stampCounter))
		declarations.append(DifferentialValueCreationStamp.counterDeclaration(named: orderCounter))
		source = declarations.joined(separator: "\n\n") + "\n"
		self.rootNames = rootNames
		self.rootPropertyLabels = rootPropertyLabels
		forwardingTypeNames = (0..<screenCount).filter { forwards[$0] }.map { name("S\($0)") }
		closureForwardingTypeNames = Set(closureForwarders.map { name("S\($0)") })
		var shapes = [screenCount <= 3 ? "fewScreens" : screenCount <= 5 ? "someScreens" : "manyScreens"]
		if forwards.contains(true) {
			shapes.append("forwards")
		}
		if (0..<screenCount).contains(where: { edges[$0].contains($0) }) {
			shapes.append("opensItself")
		}
		if declaredModels.contains(where: { !$0.isEmpty }) {
			shapes.append("declaresModel")
		}
		if receivesModel {
			shapes.append("receivesModel")
		}
		if buildsAnyTypeBetween {
			shapes.append("typeBetween")
		}
		if holdsScreenByValue {
			shapes.append("screenByValue")
		}
		if rootNames.count == 2 {
			shapes.append("twoRoots")
		}
		if renames {
			shapes.append("renames")
		}
		if !closureForwarders.isEmpty {
			shapes.append("escapingName")
		}
		if erases {
			shapes.append("erases")
		}
		if receivesBuilder {
			shapes.append("receivesBuilder")
		}
		if holdsSendableWrapper {
			shapes.append("sendableWrapper")
		}
		self.shapes = shapes
	}

	private struct Property {
		let attribute: String
		let label: String
		let type: String
		/// The parameter's type in the initializer, which may declare it `@escaping`.
		let initializerType: String

		init(attribute: String, label: String, type: String, initializerType: String? = nil) {
			self.attribute = attribute
			self.label = label
			self.type = type
			self.initializerType = initializerType ?? type
		}

		static func received(_ label: String, _ type: String) -> Property {
			Property(attribute: "@Received", label: label, type: type)
		}
	}
}

/// A random number generator whose draws a seed fixes on every platform.
private struct SplitMix64 {
	private var state: UInt64

	init(seed: UInt64) {
		state = seed &* 0x9E3779B97F4A7C15 &+ 0x2545F4914F6CDD1D
	}

	mutating func next() -> UInt64 {
		state &+= 0x9E3779B97F4A7C15
		var value = state
		value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
		value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
		return value ^ (value >> 31)
	}

	/// A value in `0..<1`.
	mutating func unit() -> Double {
		Double(next() >> 11) / Double(UInt64(1) << 53)
	}

	mutating func chance(_ probability: Double) -> Bool {
		unit() < probability
	}

	mutating func int(in range: ClosedRange<Int>) -> Int {
		range.lowerBound + Int(next() % UInt64(range.count))
	}

	mutating func shuffle(_ elements: inout [some Any]) {
		guard elements.count > 1 else { return }
		for index in stride(from: elements.count - 1, to: 0, by: -1) {
			elements.swapAt(index, Int(next() % UInt64(index + 1)))
		}
	}

	mutating func sample<Element>(from elements: [Element], count: Int) -> [Element] {
		var elements = elements
		shuffle(&elements)
		return Array(elements.prefix(count))
	}
}
