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

/// The received properties of the scopes of a cycle are completed in passes over the cycle, once per scope and pass,
/// before any walk along the cycle's paths (`cycle-generation.md`, "Walks"). Each test runs `generate` with the passes and
/// without them and requires the same outcome, the generated code or the diagnostics, byte for byte, and counts the
/// scopes whose received properties were collected, so that a test of a shape left to the walk shows the walk ran.
struct SafeDIToolReceivedPropertiesByComponentTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – Scaling

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_collectsReceivedPropertiesInNumbersThatGrowWithTheTypes_whenEveryTypeOfCycleOpensEveryOther() async throws {
		// Each screen opens every other, so a walk along the paths enters a screen once per order of the screens before it.
		var passCounts = [Int]()
		var pathCounts = [Int]()
		for screenCount in [4, 5, 6] {
			let fixture = Self.screensOpeningEveryOther(screenCount: screenCount, lastScreenDeclarations: [])
			let inPasses = try await run(fixture, completingByComponent: true)
			let alongPaths = try await run(fixture, completingByComponent: false)
			#expect(inPasses.outcome == alongPaths.outcome)
			passCounts.append(inPasses.collectedScopeCount)
			pathCounts.append(alongPaths.collectedScopeCount)
		}
		for (smaller, larger) in zip(pathCounts, pathCounts.dropFirst()) {
			#expect(Double(larger) / Double(smaller) > 1.9, "Along the paths the walk collects \(pathCounts) scopes")
		}
		for (smaller, larger) in zip(passCounts, passCounts.dropFirst()) {
			// One more screen is one more scope in each pass.
			#expect(larger - smaller <= 8, "In passes the walk collects \(passCounts) scopes")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_collectsSameReceivedProperties_whenTypeInstantiatesInstantiatorOfItself() async throws {
		// A cycle of one scope: `Screen0` opens itself and nothing else.
		let fixture = Self.screensOpeningEveryOther(screenCount: 1, lastScreenDeclarations: ["@Instantiated let screen0Builder: Instantiator<Screen0>"])
		let inPasses = try await run(fixture, completingByComponent: true)
		let alongPaths = try await run(fixture, completingByComponent: false)
		#expect(inPasses.outcome == alongPaths.outcome)
		#expect(inPasses.outcome.isGenerated)
		// One pass of the one scope: a second would collect it again.
		let counts = [inPasses.collectedScopeCount, alongPaths.collectedScopeCount]
		#expect(counts == [2, 2])
	}

	// MARK: Tests – Cycles with an `onlyIfAvailable` alias

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_collectsReceivedPropertiesInNumbersThatGrowWithTheTypes_whenNoReceiverRequiresOnlyIfAvailableAliasTypeOfCycleDeclares() async throws {
		// The last screen renames `service` only if available and nothing receives the rename, so no tree requires
		// `service` through it, and what each screen receives is judged property by property, in passes.
		var passCounts = [Int]()
		var pathCounts = [Int]()
		for screenCount in [4, 5, 6] {
			let fixture = Self.screensOpeningEveryOther(screenCount: screenCount, lastScreenDeclarations: ["@Received(fulfilledByDependencyNamed: \"service\", ofType: Service.self, onlyIfAvailable: true) let renamedService: Service?"])
			let inPasses = try await run(fixture, completingByComponent: true)
			let alongPaths = try await run(fixture, completingByComponent: false)
			#expect(inPasses.outcome == alongPaths.outcome)
			#expect(inPasses.outcome.isGenerated)
			passCounts.append(inPasses.collectedScopeCount)
			pathCounts.append(alongPaths.collectedScopeCount)
		}
		for (smaller, larger) in zip(pathCounts, pathCounts.dropFirst()) {
			#expect(Double(larger) / Double(smaller) > 1.9, "Along the paths the walk collects \(pathCounts) scopes")
		}
		for (smaller, larger) in zip(passCounts, passCounts.dropFirst()) {
			#expect(larger - smaller <= 8, "In passes the walk collects \(passCounts) scopes")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_collectsReceivedPropertiesInNumbersThatGrowWithTheTypes_whenTreeBeneathCycleRequiresOnlyIfAvailableAliasOfItsOwn() async throws {
		// `Reader`, beneath `Panel`, requires `Panel`'s alias of `service` only if available, so `Panel`'s tree requires
		// `service` through the alias. No screen declares `service` or an alias, so each screen's tree requires it too,
		// whichever screen a walk enters first, and the cycle above `Panel` is completed in passes.
		var passCounts = [Int]()
		var pathCounts = [Int]()
		for screenCount in [4, 5, 6] {
			let fixture = Self.screensOpeningEveryOther(screenCount: screenCount, lastScreenDeclarations: ["@Instantiated let panel: Panel"]) + [
				seamFixtureType(named: "Panel", isFinalClass: true, declarations: [
					"@Received(fulfilledByDependencyNamed: \"service\", ofType: Service.self, onlyIfAvailable: true) let renamedService: Service?",
					"@Instantiated let reader: Reader",
				]),
				seamFixtureType(named: "Reader", isFinalClass: true, declarations: ["@Received let renamedService: Service?"]),
			]
			let inPasses = try await run(fixture, completingByComponent: true)
			let alongPaths = try await run(fixture, completingByComponent: false)
			#expect(inPasses.outcome == alongPaths.outcome)
			#expect(inPasses.outcome.isGenerated)
			passCounts.append(inPasses.collectedScopeCount)
			pathCounts.append(alongPaths.collectedScopeCount)
		}
		for (smaller, larger) in zip(pathCounts, pathCounts.dropFirst()) {
			#expect(Double(larger) / Double(smaller) > 1.8, "Along the paths the walk collects \(pathCounts) scopes")
		}
		for (smaller, larger) in zip(passCounts, passCounts.dropFirst()) {
			#expect(larger - smaller <= 8, "In passes the walk collects \(passCounts) scopes")
		}
	}

	@Test(arguments: AliasRequiredThroughCycle.allCases, SafeDIToolCleanSubtreeTests.DeclarationOrder.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsWhatWalkAlongPathsReports_whenServiceReceivesBuilderOfCycleWhoseTreeRequiresItThroughOnlyIfAvailableAlias(graph: AliasRequiredThroughCycle, order: SafeDIToolCleanSubtreeTests.DeclarationOrder) async throws {
		// `Root` builds `service` and `s0Builder`, and `Service` receives `s0Builder`. A `Reader` beneath the cycle that
		// `S0` opens requires an only-if-available alias of `service`, so `s0Builder`'s tree requires `service` built
		// first: the two children of `Root` require each other. Where `Root` declares `service` first only that
		// requirement, which the passes carry out of the cycle, rejects the graph; where it declares `s0Builder` first
		// the walk rejects `service`'s receive.
		let fixture = graph.fixture(order: order)
		let inPasses = try await run(fixture, completingByComponent: true)
		let alongPaths = try await run(fixture, completingByComponent: false)
		#expect(inPasses.outcome == alongPaths.outcome)
		switch (inPasses.outcome, graph.expectedError(order: order)) {
		case let (.error(description), expectedError?):
			#expect(description == expectedError)
		case (.generated, nil):
			break
		case (.error, nil), (.generated, _?):
			Issue.record("\(graph), \(order): \(inPasses.outcome)")
		}
	}

	// MARK: Tests – Cycles left to the walk

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_collectsReceivedPropertiesAlongPaths_whenReceiverBeneathTypeOfCycleRequiresItsOnlyIfAvailableAlias() async throws {
		// `Reader`, beneath the last screen, requires that screen's alias of `service`, so the screen's tree requires
		// `service` through an alias of the cycle's own. Which trees of the cycle do depends on the screen a walk enters
		// first, so the passes' results are dropped and the cycle is walked along its paths, as without the passes.
		let fixture = Self.screensOpeningEveryOther(
			screenCount: 5,
			lastScreenDeclarations: ["@Received(fulfilledByDependencyNamed: \"service\", ofType: Service.self, onlyIfAvailable: true) let renamedService: Service?", "@Instantiated let reader: Reader"],
		) + [seamFixtureType(named: "Reader", isFinalClass: true, declarations: ["@Received let renamedService: Service?"])]
		let inPasses = try await run(fixture, completingByComponent: true)
		let alongPaths = try await run(fixture, completingByComponent: false)
		#expect(inPasses.outcome == alongPaths.outcome)
		#expect(inPasses.outcome.isGenerated)
		// Every scope the walk along the paths collects, and the passes' collections before it: with the passes'
		// results kept the first count is smaller than the second.
		let counts = [inPasses.collectedScopeCount, alongPaths.collectedScopeCount]
		#expect(counts == [43, 33])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsValueAfterBuilderItReceives_whenOnlyTypeBuilderOpensNextRenamesValueForTypeItOpens() async throws {
		// `B` and `A` open each other. `A` renames `s` only if available, and `B` requires the rename, which `Hall`
		// forwards above the `B` it opens. A walk entered at `B` takes nothing from the `B` that `A` opens, so `B`'s tree
		// requires no `s` through an alias, and `Hall` builds `bBuilder` before the `s` that receives it. The passes
		// find `A`'s alias required, by the `B` beneath it, and would have `B`'s tree require `s` first: a cycle of
		// `Hall`'s children. They leave the cycle to the walk instead.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let hallBuilder: Instantiator<Hall>"]),
			seamFixtureType(named: "Hall", isFinalClass: true, declarations: ["@Forwarded let r: S?", "@Instantiated let s: S", "@Instantiated let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "S", isFinalClass: true, declarations: ["@Received let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received let r: S?", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: [
				"@Received(fulfilledByDependencyNamed: \"s\", ofType: S.self, onlyIfAvailable: true) let r: S?",
				"@Instantiated let bBuilder: Instantiator<B>",
			]),
		]
		let inPasses = try await run(fixture, completingByComponent: true)
		let alongPaths = try await run(fixture, completingByComponent: false)
		#expect(inPasses.outcome == alongPaths.outcome)
		#expect(inPasses.outcome.isGenerated)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_collectsReceivedPropertiesAlongPaths_whenTypeOutsideCycleLeftToTheWalkOpensScreenOfIt() async throws {
		// `Root` builds `screen0Builder` and then `hallBuilder`, and `Hall` opens `Screen2`. The walk from `Screen0` leaves
		// `Screen2` without complete received properties, so `Hall`, asked next, reaches a scope left to the walk and is
		// left to it too.
		let fixture = Self.screensOpeningEveryOther(
			screenCount: 5,
			lastScreenDeclarations: ["@Received(fulfilledByDependencyNamed: \"service\", ofType: Service.self, onlyIfAvailable: true) let renamedService: Service?", "@Instantiated let reader: Reader"],
			rootDeclarations: ["@Instantiated let hallBuilder: Instantiator<Hall>"],
		) + [
			seamFixtureType(named: "Hall", isFinalClass: true, declarations: ["@Instantiated let screen2Builder: Instantiator<Screen2>"]),
			seamFixtureType(named: "Reader", isFinalClass: true, declarations: ["@Received let renamedService: Service?"]),
		]
		let inPasses = try await run(fixture, completingByComponent: true)
		let alongPaths = try await run(fixture, completingByComponent: false)
		#expect(inPasses.outcome == alongPaths.outcome)
		#expect(inPasses.outcome.isGenerated)
		let counts = [inPasses.collectedScopeCount, alongPaths.collectedScopeCount]
		#expect(counts == [44, 34])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_walksFillOfPublicMockCall_whenFillOpensCycleThatDeclaresOnlyIfAvailableAlias() async throws {
		// `Root.mock()` calls `F`’s public mock and fills its `api` with `Live`, whose `A` and `B` open each other, and `A`
		// declares an `onlyIfAvailable` alias. The cycle is left to the walk along its paths, and so is every scope that
		// reaches it: the fill, and the call that passes it, whose fills that walk then enters after its children.
		let modules = Self.modulesWhoseCallFillsBuilderWithCycleDeclaringAlias(fillingSecondBuilder: false)
		let inPasses = try await run(modules, completingByComponent: true)
		let alongPaths = try await run(modules, completingByComponent: false)
		#expect(inPasses.outcome == alongPaths.outcome)
		#expect(inPasses.outcome.isGenerated)
		// The two passes over `A` and `B`, then the walk of them along their paths with the fill and the call: with the
		// passes' results kept, or the fill and the call not left to the walk, fewer scopes are collected.
		let counts = [inPasses.collectedScopeCount, alongPaths.collectedScopeCount]
		#expect(counts == [70, 34])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesCollectedFillOfPublicMockCall_whenAnotherFillOfCallOpensCycleThatDeclaresOnlyIfAvailableAlias() async throws {
		// `F` instantiates a `Log` too, which `App` fills with `Plain`, a type that receives nothing. The call is left to
		// the walk for its fill of `api`, and that walk takes what was already collected for `Plain` without walking it.
		let modules = Self.modulesWhoseCallFillsBuilderWithCycleDeclaringAlias(fillingSecondBuilder: true)
		let inPasses = try await run(modules, completingByComponent: true)
		let alongPaths = try await run(modules, completingByComponent: false)
		#expect(inPasses.outcome == alongPaths.outcome)
		#expect(inPasses.outcome.isGenerated)
	}

	// MARK: Tests – Drawn graphs

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_collectsSameReceivedProperties_whenScreensWithOnlyIfAvailableAliasesAreDrawnFromEachSeed() async throws {
		// A draw of the shapes above: screens that open each other in a ring, some of which rename `service` only if
		// available, receive the rename, build a reader of it or declare `service` themselves, beneath roots and halls
		// that may rename it too, with every type's mock generated in half the graphs. Every graph is run in passes and
		// along the paths. The counts show the draw reaches what it is for: graphs the tool accepts, graphs it rejects,
		// those it rejects for a dependency cycle, and graphs whose passes collected another number of scopes than the
		// walk along the paths. Seed 46 fails when the passes drop the properties whose renames a cycle's tree requires,
		// and seed 17 when a cycle whose own rename a member requires is kept as the passes completed it.
		var acceptedCount = 0
		var rejectedCount = 0
		var dependencyCycleCount = 0
		var inPassesCount = 0
		for seed in 0..<Self.aliasDrawSeedCount {
			let fixture = Self.screensWithOnlyIfAvailableAliases(seed: seed)
			let inPasses = try await run(fixture, completingByComponent: true)
			let alongPaths = try await run(fixture, completingByComponent: false)
			#expect(inPasses.outcome == alongPaths.outcome, "seed \(seed)")
			switch inPasses.outcome {
			case .generated:
				acceptedCount += 1
			case let .error(description):
				rejectedCount += 1
				if description.contains("error: Dependency cycle") {
					dependencyCycleCount += 1
				}
			}
			if inPasses.collectedScopeCount != alongPaths.collectedScopeCount {
				inPassesCount += 1
			}
		}
		let counts = [acceptedCount, rejectedCount, dependencyCycleCount, inPassesCount]
		#expect(counts == [28, 122, 59, 47])
	}

	// MARK: Tests – Diagnostics

	@Test(arguments: SafeDIToolReceivedPropertiesByComponentTests.permutations(of: ["b", "e", "pBuilder", "qBuilder"]))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsSameSiblingCycleError_whateverOrderRootDeclaresChildrenThatRequireEachOtherThroughOneCycle(order: [String]) async throws {
		// `B` receives `pBuilder` and `E` receives `qBuilder`, whose trees, one cycle of instantiators, receive `b` and
		// `e`: each of `b` and `e` requires itself through either builder. Which is reported follows no order of `Root`'s
		// children, and neither does it follow which of the cycle's scopes is collected first.
		let fixture = Self.siblingsRequiringEachOtherThroughOneCycle(order: order)
		let inPasses = try await run(fixture, completingByComponent: true)
		let alongPaths = try await run(fixture, completingByComponent: false)
		#expect(inPasses.outcome == alongPaths.outcome)
		#expect(inPasses.outcome == .error(Self.siblingsRequiringEachOtherError), "Root builds \(order)")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// What `generate` produced: its generated files, or its diagnostics.
	private enum Outcome: Equatable {
		case generated([String: String])
		case error(String)

		var isGenerated: Bool {
			switch self {
			case .generated:
				true
			case .error:
				false
			}
		}
	}

	private struct Run {
		let outcome: Outcome
		let collectedScopeCount: Int
	}

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func run(_ fixture: [String], completingByComponent: Bool) async throws -> Run {
		let (stream, continuation) = AsyncStream.makeStream(of: ValidationWalkObservation.self)
		let outcome: Outcome
		do {
			let output = try await ValidationWalkObservation.$completesReceivedPropertiesByComponent.withValue(completingByComponent) {
				try await ValidationWalkObservation.$observer.withValue(TaskLocalFunction { continuation.yield($0) }) {
					try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
				}
			}
			outcome = .generated((output.generatedFiles ?? [:]).mapValues(Self.withFixtureNames))
		} catch let error as SafeDIToolTestError {
			outcome = .error(Self.withFixtureNames(error.description))
		}
		continuation.finish()
		var collectedScopeCount = 0
		for await observation in stream {
			switch observation {
			case .collectedReceivedPropertiesOfScope:
				collectedScopeCount += 1
			case .validatedScope,
			     .skippedCleanSubtree,
			     .keyedSubtree:
				break
			}
		}
		return Run(outcome: outcome, collectedScopeCount: collectedScopeCount)
	}

	/// `text` with each fixture's directory left out, so two runs' diagnostics, and the `#sourceLocation` directives of
	/// their generated code, compare equal.
	private static func withFixtureNames(_ text: String) -> String {
		text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
			guard let swiftRange = line.range(of: ".swift"),
			      let slash = line[..<swiftRange.lowerBound].lastIndex(of: "/"),
			      let firstSlash = line.firstIndex(of: "/")
			else { return String(line) }
			return String(line[..<firstSlash]) + String(line[line.index(after: slash)...])
		}.joined(separator: "\n")
	}

	/// Every order of `elements`.
	private static func permutations(of elements: [String]) -> [[String]] {
		guard let first = elements.first else { return [[]] }
		return permutations(of: Array(elements.dropFirst())).flatMap { permutation in
			(0...permutation.count).map { index in
				var inserted = permutation
				inserted.insert(first, at: index)
				return inserted
			}
		}
	}

	/// Graphs in which `Root` builds a `service` that receives `s0Builder`, beside `s0Builder`, whose tree holds a cycle
	/// and a `Reader` of an only-if-available alias of `service`.
	enum AliasRequiredThroughCycle: CaseIterable {
		/// `S0` and `S1` open each other, and `S1` builds `Panel`, which declares the alias and builds its `Reader`: the
		/// cycle is completed in passes, which carry the requirement out of it.
		case panelBeneathCycleDeclaresAlias
		/// The same graph with a `Reader` that receives nothing, so nothing requires the alias.
		case panelBeneathCycleDeclaresAliasNothingReads
		/// `S1` declares the alias itself and builds the `Reader`: the cycle is left to the walk.
		case typeOfCycleDeclaresAlias
		/// `S0` opens only itself and builds `Panel`.
		case panelBeneathTypeThatOpensItselfDeclaresAlias
		/// `S0` opens only itself, declares the alias and builds the `Reader`.
		case typeThatOpensItselfDeclaresAlias

		private static let renamedService = "@Received(fulfilledByDependencyNamed: \"service\", ofType: Service.self, onlyIfAvailable: true) let renamedService: Service?"

		private var types: [(name: String, declarations: [String])] {
			let panel = ("Panel", [Self.renamedService, "@Instantiated let reader: Reader"])
			let reader = ("Reader", self == .panelBeneathCycleDeclaresAliasNothingReads ? [] : ["@Received let renamedService: Service?"])
			let screens: [(String, [String])] = switch self {
			case .panelBeneathCycleDeclaresAlias, .panelBeneathCycleDeclaresAliasNothingReads:
				[
					("S0", ["@Instantiated let s1Builder: Instantiator<S1>"]),
					("S1", ["@Instantiated let s0Builder: Instantiator<S0>", "@Instantiated let panel: Panel"]),
					panel,
				]
			case .typeOfCycleDeclaresAlias:
				[
					("S0", ["@Instantiated let s1Builder: Instantiator<S1>"]),
					("S1", ["@Instantiated let s0Builder: Instantiator<S0>", Self.renamedService, "@Instantiated let reader: Reader"]),
				]
			case .panelBeneathTypeThatOpensItselfDeclaresAlias:
				[
					("S0", ["@Instantiated let s0Builder: Instantiator<S0>", "@Instantiated let panel: Panel"]),
					panel,
				]
			case .typeThatOpensItselfDeclaresAlias:
				[
					("S0", ["@Instantiated let s0Builder: Instantiator<S0>", Self.renamedService, "@Instantiated let reader: Reader"]),
				]
			}
			return [
				("Root", ["@Instantiated let service: Service", "@Instantiated let s0Builder: Instantiator<S0>"]),
				("Service", ["@Received let s0Builder: Instantiator<S0>"]),
			] + screens + [reader]
		}

		/// What main reports for the graph in `order`: `nil` where it generates.
		func expectedError(order: SafeDIToolCleanSubtreeTests.DeclarationOrder) -> String? {
			switch (self, order) {
			case (.panelBeneathCycleDeclaresAliasNothingReads, _):
				nil
			case (.typeThatOpensItselfDeclaresAlias, _):
				"""
				Service.swift:7:5: error: Dependency cycle: @Instantiated `s0Builder: Instantiator<S0>` -> @Received `renamedService: Service?` -> @Received `service: Service` -> @Received `s0Builder: Instantiator<S0>`. `s0Builder: Instantiator<S0>` is received while it is still being instantiated. `renamedService: Service?` renames `service: Service` only if available, so a type that receives `renamedService` without `onlyIfAvailable` must be built after `service: Service`. Receive `renamedService` with `@Received(onlyIfAvailable: true)` to be passed `nil` where `service: Service` cannot be built first.
				"""
			case (.panelBeneathCycleDeclaresAlias, .written), (.typeOfCycleDeclaresAlias, .written), (.panelBeneathTypeThatOpensItselfDeclaresAlias, .written):
				// `service` is declared first: the check of children that require each other reports it.
				"""
				Reader.swift:7:5: error: Dependency cycle: @Instantiated `service: Service` -> @Received `s0Builder: Instantiator<S0>` -> @Received `service: Service`. `service: Service` is received while it is still being instantiated. `renamedService: Service?` renames `service: Service` only if available, so a type that receives `renamedService` without `onlyIfAvailable` must be built after `service: Service`. Receive `renamedService` with `@Received(onlyIfAvailable: true)` to be passed `nil` where `service: Service` cannot be built first.
				"""
			case (.panelBeneathCycleDeclaresAlias, .reversed), (.panelBeneathCycleDeclaresAlias, .rootRotated), (.panelBeneathCycleDeclaresAlias, .rootRotatedAndOthersReversed),
			     (.typeOfCycleDeclaresAlias, .reversed), (.typeOfCycleDeclaresAlias, .rootRotated), (.typeOfCycleDeclaresAlias, .rootRotatedAndOthersReversed),
			     (.panelBeneathTypeThatOpensItselfDeclaresAlias, .reversed), (.panelBeneathTypeThatOpensItselfDeclaresAlias, .rootRotated), (.panelBeneathTypeThatOpensItselfDeclaresAlias, .rootRotatedAndOthersReversed):
				// `s0Builder` is declared first: the walk reports `service`'s receive of it.
				"""
				Service.swift:7:5: error: Dependency cycle: @Instantiated `s0Builder: Instantiator<S0>` -> @Received `service: Service` -> @Received `s0Builder: Instantiator<S0>`. `s0Builder: Instantiator<S0>` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
				"""
			}
		}

		func fixture(order: SafeDIToolCleanSubtreeTests.DeclarationOrder) -> [String] {
			types.map { name, declarations in
				seamFixtureType(named: name, isRoot: name == "Root", isFinalClass: true, declarations: order.ordered(declarations, ofRoot: name == "Root"))
			}
		}
	}

	/// screen's builder and `rootDeclarations`; the last screen also declares `lastScreenDeclarations`.
	private static func screensOpeningEveryOther(screenCount: Int, lastScreenDeclarations: [String], rootDeclarations: [String] = []) -> [String] {
		var fixture = [String]()
		for index in 0..<screenCount {
			fixture.append(seamFixtureType(
				named: "Screen\(index)",
				isFinalClass: true,
				declarations: ["@Received let service: Service"]
					+ (0..<screenCount).filter { $0 != index }.map { "@Instantiated let screen\($0)Builder: Instantiator<Screen\($0)>" }
					+ (index == screenCount - 1 ? lastScreenDeclarations : []),
			))
		}
		fixture.append(seamFixtureType(named: "Service", isFinalClass: true, declarations: []))
		fixture.append(seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let service: Service", "@Instantiated let screen0Builder: Instantiator<Screen0>"] + rootDeclarations))
		return fixture
	}

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func run(_ modules: [ModuleFixture], completingByComponent: Bool) async throws -> Run {
		let (stream, continuation) = AsyncStream.makeStream(of: ValidationWalkObservation.self)
		let outcome: Outcome
		do {
			let output = try await ValidationWalkObservation.$completesReceivedPropertiesByComponent.withValue(completingByComponent) {
				try await ValidationWalkObservation.$observer.withValue(TaskLocalFunction { continuation.yield($0) }) {
					try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
				}
			}
			outcome = .generated((output.modules["App"]?.generatedFiles ?? [:]).mapValues(Self.withFixtureNames))
		} catch let error as SafeDIToolTestError {
			outcome = .error(Self.withFixtureNames(error.description))
		}
		continuation.finish()
		var collectedScopeCount = 0
		for await observation in stream {
			switch observation {
			case .collectedReceivedPropertiesOfScope:
				collectedScopeCount += 1
			case .validatedScope,
			     .skippedCleanSubtree,
			     .keyedSubtree:
				break
			}
		}
		return Run(outcome: outcome, collectedScopeCount: collectedScopeCount)
	}

	/// `F`, a public mock of `Feat`, instantiates an `Api` no declaration of its module fulfills. `App` fulfills it with
	/// `Live`, whose `A` and `B` open each other, and `A` declares an `onlyIfAvailable` alias of `user`. With
	/// `fillingSecondBuilder`, `F` instantiates a `Log` too, which `App` fulfills with `Plain`.
	private static func modulesWhoseCallFillsBuilderWithCycleDeclaringAlias(fillingSecondBuilder: Bool) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Base", packageName: "Base", swiftFileContentByFilePath: [
				"BaseTypes.swift": """
				import SafeDI

				public protocol Api {}

				public protocol Log {}

				@Instantiable
				public struct User: Instantiable {
				    public init() {}
				}
				""",
			]),
			ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContentByFilePath: [
				"FeatTypes.swift": """
				import Base
				import SafeDI

				@Instantiable(generateMock: .public)
				public struct F: Instantiable {
				    init(user: User, api: any Api\(fillingSecondBuilder ? ", log: any Log" : "")) {
				        self.user = user
				        self.api = api
				        \(fillingSecondBuilder ? "self.log = log" : "")
				    }

				    @Received let user: User
				    @Instantiated let api: any Api
				    \(fillingSecondBuilder ? "@Instantiated let log: any Log" : "")
				}
				""",
			], dependencies: ["Base"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"AppTypes.swift": """
				import Base
				import Feat
				import SafeDI

				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				public struct Live: Api, Instantiable {
				    public init(aBuilder: Instantiator<A>) {
				        self.aBuilder = aBuilder
				    }

				    @Instantiated let aBuilder: Instantiator<A>
				}

				@Instantiable(fulfillingAdditionalTypes: [Log.self])
				public struct Plain: Log, Instantiable {
				    public init() {}
				}

				@Instantiable
				public final class A: Instantiable {
				    public init(bBuilder: Instantiator<B>, renamedUser: User?, reader: Reader) {
				        self.bBuilder = bBuilder
				        self.renamedUser = renamedUser
				        self.reader = reader
				    }

				    @Instantiated let bBuilder: Instantiator<B>
				    @Received(fulfilledByDependencyNamed: "user", ofType: User.self, onlyIfAvailable: true) let renamedUser: User?
				    @Instantiated let reader: Reader
				}

				@Instantiable
				public final class Reader: Instantiable {
				    public init(renamedUser: User?) {
				        self.renamedUser = renamedUser
				    }

				    @Received let renamedUser: User?
				}

				@Instantiable
				public final class B: Instantiable {
				    public init(aBuilder: Instantiator<A>) {
				        self.aBuilder = aBuilder
				    }

				    @Instantiated let aBuilder: Instantiator<A>
				}

				@Instantiable(generateMock: true)
				public struct Root: Instantiable {
				    public init(f: F) {
				        self.f = f
				    }

				    @Instantiated let f: F
				}
				""",
			], dependencies: ["Base", "Feat"]),
		]
	}

	static let aliasDrawSeedCount: UInt64 = 150

	/// Two to four screens that open each other in a ring, drawn from `seed`: each may also open a second screen, rename
	/// `service` only if available, receive the rename or `service`, declare `service` itself, and build a `Reader`, which
	/// requires the rename, by value or through an instantiator. One or two roots each reach the ring through entries
	/// that may declare `service` or rename it; the root may too. In half the graphs every type but a root generates its
	/// mock, whose promotion collects each tree's received properties.
	/// A second stream then draws what can close a dependency cycle through a rename, described where it is drawn.
	static func screensWithOnlyIfAvailableAliases(seed: UInt64) -> [String] {
		var random = GraphFuzzerRandomNumberGenerator(seed: seed ^ 0x416C696173526E67)
		let rename = "@Received(fulfilledByDependencyNamed: \"service\", ofType: Service.self, onlyIfAvailable: true) let renamedService: Service?"
		let screenCount = random.integer(in: 2...4)
		func screenBuilder(_ index: Int) -> String {
			"@Instantiated let screen\(index)Builder: Instantiator<Screen\(index)>"
		}
		var types = [(name: String, isRoot: Bool, declarations: [String])]()
		for index in 0..<screenCount {
			var declarations = [screenBuilder((index + 1) % screenCount)]
			if screenCount > 2, random.percentChance(35) {
				declarations.append(screenBuilder((index + 2) % screenCount))
			}
			switch random.integer(in: 0...9) {
			case 0...2:
				declarations.append(rename)
			case 3...4:
				declarations.append("@Received let renamedService: Service?")
			case 5:
				declarations.append("@Received(onlyIfAvailable: true) let renamedService: Service?")
			default:
				break
			}
			switch random.integer(in: 0...9) {
			case 0...1:
				declarations.append("@Received let service: Service")
			case 2:
				declarations.append("@Instantiated let service: Service")
			default:
				break
			}
			switch random.integer(in: 0...9) {
			case 0...2:
				declarations.append("@Instantiated let reader: Reader")
			case 3:
				declarations.append("@Instantiated let readerBuilder: Instantiator<Reader>")
			default:
				break
			}
			types.append(("Screen\(index)", false, declarations))
		}
		var entryCount = 0
		var entryProperties = [String]()
		for rootIndex in 0..<random.integer(in: 1...2) {
			var rootDeclarations = [String]()
			if random.percentChance(70) {
				rootDeclarations.append("@Instantiated let service: Service")
				if random.percentChance(30) {
					rootDeclarations.append(rename)
				}
			}
			for _ in 0..<random.integer(in: 1...2) {
				var entryDeclarations = [screenBuilder(random.integer(in: 0...screenCount - 1))]
				switch random.integer(in: 0...9) {
				case 0...2:
					entryDeclarations.append("@Instantiated let service: Service")
					entryDeclarations.append(rename)
				case 3...4:
					entryDeclarations.append(rename)
				case 5:
					entryDeclarations.append("@Instantiated let service: Service")
				default:
					break
				}
				types.append(("Entry\(entryCount)", false, entryDeclarations))
				let entryProperty = random.percentChance(50)
					? "entry\(entryCount): Entry\(entryCount)"
					: "entry\(entryCount)Builder: Instantiator<Entry\(entryCount)>"
				rootDeclarations.append("@Instantiated let \(entryProperty)")
				entryProperties.append(entryProperty)
				entryCount += 1
			}
			types.append(("Root\(rootIndex)", true, rootDeclarations))
		}
		// What can close a dependency cycle through a rename, on a stream of its own, so that the graphs without it are
		// the graphs above. In two graphs of ten `Service` receives an entry or a screen's builder. In eight, a root of
		// the shape is the only type that declares `service`, and `Service` receives a property on the way from that
		// root to the ring: one of three lobbies, each of which opens one screen (`Root8`); the builder every root holds
		// itself, so that the roots' paths differ only in the one that declares `service` (`Root9`); the builder of the
		// ring, one screen of which builds a `Panel` that renames `service` beneath the ring; or the builder a `Hall`
		// opens beside its own `service`, the rename forwarded to it, for a screen that requires the rename and is
		// opened by a screen that declares it. Beside them, a rename of the rename with a reader of its own, built in
		// two types and now and then in `Service`, and a screen that also opens itself.
		var cycleRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ 0x4379636C65526E67)
		let service = "@Instantiated let service: Service"
		let receivedScreenIndex = cycleRandom.integer(in: 0...screenCount - 1)
		var receivedProperty: String? = String(screenBuilder(receivedScreenIndex).dropFirst("@Instantiated let ".count))
		let shape = cycleRandom.integer(in: 0...9)
		if shape >= 2 {
			for index in types.indices {
				// A root that no longer declares `service` cannot rename it: nothing passes a root a dependency.
				let isRoot = types[index].isRoot
				types[index].declarations.removeAll { $0 == service || $0 == "@Received let service: Service" || (isRoot && $0 == rename) }
			}
		}
		switch shape {
		case 0:
			receivedProperty = nil
		case 1:
			if cycleRandom.percentChance(60) {
				receivedProperty = cycleRandom.element(of: entryProperties)
			}
		case 2...3:
			for lobbyIndex in 0...2 {
				types.append(("Lobby\(lobbyIndex)", false, [screenBuilder(receivedScreenIndex)]))
			}
			types.append(("Root8", true, ["@Instantiated let lobby0: Lobby0", "@Instantiated let lobby1: Lobby1", "@Instantiated let lobby2: Lobby2", service]))
			let lobbyIndex = cycleRandom.integer(in: 1...2)
			receivedProperty = "lobby\(lobbyIndex): Lobby\(lobbyIndex)"
		case 4...5:
			for index in types.indices where types[index].isRoot {
				types[index].declarations.insert(screenBuilder(receivedScreenIndex), at: 0)
			}
			types.append(("Root9", true, [screenBuilder(receivedScreenIndex), service]))
		case 6...7:
			types[cycleRandom.integer(in: 0...screenCount - 1)].declarations.append("@Instantiated let panel: Panel")
			types.append(("Panel", false, [rename, "@Instantiated let reader: Reader"]))
			types.append(("Root8", true, [screenBuilder(receivedScreenIndex), service]))
		default:
			let renamedServiceDeclarations = [rename, "@Received let renamedService: Service?", "@Received(onlyIfAvailable: true) let renamedService: Service?"]
			let openingScreenIndex = (receivedScreenIndex + screenCount - 1) % screenCount
			types[receivedScreenIndex].declarations.removeAll { renamedServiceDeclarations.contains($0) }
			types[receivedScreenIndex].declarations.append("@Received let renamedService: Service?")
			types[openingScreenIndex].declarations.removeAll { renamedServiceDeclarations.contains($0) }
			types[openingScreenIndex].declarations.append(rename)
			types.append(("Hall", false, ["@Forwarded let renamedService: Service?", service, screenBuilder(receivedScreenIndex)]))
			types.append(("Root8", true, ["@Instantiated let hallBuilder: Instantiator<Hall>"]))
		}
		var serviceDeclarations = [String]()
		if let receivedProperty {
			serviceDeclarations.append(cycleRandom.percentChance(30)
				? "@Received(onlyIfAvailable: true) let \(receivedProperty)?"
				: "@Received let \(receivedProperty)")
		}
		if cycleRandom.percentChance(40) {
			for _ in 0..<2 {
				let typeIndex = cycleRandom.integer(in: 0...screenCount - 1)
				if !types[typeIndex].declarations.contains("@Instantiated let relay: Relay") {
					types[typeIndex].declarations.append("@Instantiated let relay: Relay")
				}
			}
			if cycleRandom.percentChance(50) {
				serviceDeclarations.append("@Instantiated let relay: Relay")
				for index in types.indices where types[index].name == "Root8" && types[index].declarations.contains(service) {
					types[index].declarations.append(rename)
				}
			}
			types += [
				("Relay", false, [
					"@Received(fulfilledByDependencyNamed: \"renamedService\", ofType: Service?.self, onlyIfAvailable: true) let renamedAgain: Service?",
					"@Instantiated let relayReader: RelayReader",
				]),
				("RelayReader", false, ["@Received let renamedAgain: Service?"]),
			]
		}
		if cycleRandom.percentChance(25) {
			let screenIndex = cycleRandom.integer(in: 0...screenCount - 1)
			if !types[screenIndex].declarations.contains(screenBuilder(screenIndex)) {
				types[screenIndex].declarations.append(screenBuilder(screenIndex))
			}
		}
		types += [
			("Reader", false, ["@Received let renamedService: Service?"]),
			("Service", false, serviceDeclarations),
		]
		let generatesMocks = random.percentChance(50)
		return types.map { type in
			let fixture = seamFixtureType(named: type.name, isRoot: type.isRoot, isFinalClass: true, declarations: type.declarations)
			return generatesMocks && !type.isRoot
				? fixture.replacingOccurrences(of: "@Instantiable\npublic", with: "@Instantiable(generateMock: true)\npublic")
				: fixture
		}
	}

	/// `Root` builds `b`, `e`, `pBuilder` and `qBuilder` in `order`; the builders enter one cycle of `P0`, `P1` and `P2`.
	private static func siblingsRequiringEachOtherThroughOneCycle(order: [String]) -> [String] {
		let types = ["b": "B", "e": "E", "pBuilder": "Instantiator<P0>", "qBuilder": "Instantiator<P1>"]
		return [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: order.map { "@Instantiated let \($0): \(types[$0] ?? "")" }),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received let pBuilder: Instantiator<P0>"]),
			seamFixtureType(named: "E", isFinalClass: true, declarations: ["@Received let qBuilder: Instantiator<P1>"]),
			seamFixtureType(named: "P0", isFinalClass: true, declarations: ["@Instantiated let p1Builder: Instantiator<P1>", "@Instantiated let p2Builder: Instantiator<P2>"]),
			seamFixtureType(named: "P1", isFinalClass: true, declarations: ["@Instantiated let p0Builder: Instantiator<P0>", "@Instantiated let p2Builder: Instantiator<P2>", "@Received let e: E"]),
			seamFixtureType(named: "P2", isFinalClass: true, declarations: ["@Instantiated let p0Builder: Instantiator<P0>", "@Instantiated let p1Builder: Instantiator<P1>", "@Received let b: B"]),
		]
	}

	private static let siblingsRequiringEachOtherError = """
	E.swift:7:5: error: Dependency cycle: @Instantiated `qBuilder: Instantiator<P1>` -> @Received `e: E` -> @Received `qBuilder: Instantiator<P1>`. `qBuilder: Instantiator<P1>` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
	"""
}
