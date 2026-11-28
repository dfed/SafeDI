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

/// The per-type facts' column of whether each fill of a seam call builds in a `@Sendable` function
/// (`TypeFactsFill.buildsInSendableFunction`), against what the tree decides (`ScopeGenerator.buildsInSendableFunction(ofFill:)`):
/// `Top`, a seam of `Feature`, passes up the places `first` of `SubA` and `second` of `SubB`, which `Host`, a seam of
/// `Middle`, fills; `DefaultFirst`, `first`'s fill, builds `SubB` again, which passes the enclosing fill of `second` on.
struct SafeDIToolSeamFillSendabilityFactsTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try? FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func typeFacts_marksFillSendable_whenCallInsideAnotherFillReentersItThroughSendableInstantiator() async throws {
		// `DefaultFirst` builds `SubB` again in a `SendableInstantiator`'s `@Sendable` function, which does not enclose
		// `Top`'s call and refers to `second`: `second` builds in a `@Sendable` function, `first` does not, though the seam
		// takes neither `@Sendable`.
		let edges = try await fillEdges(defaultFirstDeclarations: ["@Instantiated let subBBuilder: SendableInstantiator<SubB>"], middleTypes: []).edges

		#expect(edges == [
			"Top as top: Top -> DefaultFirst as first: any First fill: column false, hole false, tree false",
			"Top as top: Top -> DefaultSecond as second: any Second fill: column true, hole false, tree true",
			"SubB as subBBuilder: SendableInstantiator<SubB> -> DefaultSecond as second: any Second fill: column true, hole false, tree true",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func typeFacts_marksFillSendable_whenCycleMakesFunctionOfReenteringCallSendable() async throws {
		// `Loop`'s builder function is plain where `DefaultFirst` builds it, but `Inner`, built in a `SendableInstantiator`,
		// closes a cycle on it, which makes it `@Sendable`: `Loop`'s call of `SubB` refers to `second` from it. `Loop` is in
		// the cycle `Inner`'s `SendableInstantiator` opens, so the fold refuses its column, and with it `second`'s, which
		// the tree agrees with here.
		let edges = try await fillEdges(
			defaultFirstDeclarations: ["@Instantiated let loopBuilder: Instantiator<Loop>"],
			middleTypes: [
				seamFixtureType(named: "Loop", declarations: ["@Instantiated let innerBuilder: SendableInstantiator<Inner>", "@Instantiated let subB: SubB"]),
				seamFixtureType(named: "Inner", declarations: ["@Instantiated let loopBuilder: Instantiator<Loop>"]),
			],
		).edges

		#expect(edges == [
			"Top as top: Top -> DefaultFirst as first: any First fill: column false, hole false, tree false",
			"Top as top: Top -> DefaultSecond as second: any Second fill: column true, hole false, tree true, refused dependsOnRefusedNode",
			"SubB as subB: SubB -> DefaultSecond as second: any Second fill: column true, hole false, tree true, refused dependsOnRefusedNode",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func typeFacts_foldsFillSendabilityInWorkLinearInCalls_whenFillsNestCallsOfSeamsDeep() async throws {
		// `Root` calls `Seam0`, whose place `Impl0` fills by calling `Seam1`, and so on, n calls deep: each call is a node
		// and a fill edge, and the keys of each call's fills are dropped where the call resolves them, so the fold does
		// work linear in the calls. A summary that kept every key beneath it, or a walk per path, would grow with n².
		var work = [Int]()
		for depth in [8, 32] {
			var core = [String]()
			var app = [String]()
			for index in 0..<depth {
				core.append("public protocol Place\(index) {}")
				core.append(seamFixtureType(named: "Seam\(index)", isSeam: true, declarations: ["@Instantiated let place\(index): any Place\(index)"]))
				let declarations = index + 1 < depth ? ["@Instantiated let seam\(index + 1): Seam\(index + 1)"] : []
				app.append(SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "Impl\(index)", fulfilling: "Place\(index)", declarations: declarations))
			}
			app.append(seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let seam0: Seam0"]))
			let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: core, app: app)
			let (stream, continuation) = AsyncStream.makeStream(of: GenerationWork.self)
			try await GenerationWork.$observer.withValue({ continuation.yield($0) }) {
				_ = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: depth == 8 ? .recordingIssues : .skipped, filesToDelete: &filesToDelete)
			}
			continuation.finish()
			var count = 0
			for await step in stream where step.step == .foldingFillSendability {
				count += step.elementCount
			}
			work.append(count)
		}
		#expect(work == [64, 256])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func typeFacts_marksNodeSendable_whenFillBuildsFunctionCycleClosedInsideSendableInstantiatorRefersTo() async throws {
		// `Desk`'s fill of `parcel` builds `Alpha` through a plain `alphaBuilder`, whose function a cycle closing inside
		// `Beta`'s `SendableInstantiator` refers to, which makes it `@Sendable`: the edge into `Alpha` opens no `@Sendable`
		// function, the node's column says it builds in one. `Alpha` is in the cycle `Beta`'s `SendableInstantiator` opens,
		// so the fold refuses its column, which the tree's places agree with.
		let modules = [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Parcel {}",
				seamFixtureType(named: "Desk", isSeam: true, declarations: ["@Instantiated let parcel: any Parcel"]),
			]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: (Self.sendableCycleDeclarations + [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultParcel", fulfilling: "Parcel", declarations: ["@Instantiated let credential: Credential", "@Instantiated let alphaBuilder: Instantiator<Alpha>"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let desk: Desk"]),
			]).map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
		let report = try await Self.report(ofRoot: "Root") {
			try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		}

		#expect(Self.nodeSendability(of: report) == [
			"Root: column false, tree false",
			"Desk as desk: Desk: column false, tree false",
			"DefaultParcel as parcel: any Parcel fill: column false, tree false",
			"Credential as credential: Credential: column false, tree false",
			"Alpha as alphaBuilder: Instantiator<Alpha>: column true, tree true, refused cycleEnteredAtAnotherNode",
			"Beta as betaBuilder: SendableInstantiator<Beta>: column true, tree true",
		])
		#expect(TypeFactsChecks.findings(of: report).findingsByCheck[40] == nil)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func typeFacts_marksNodeSendable_whenRootBuildsFunctionCycleClosedInsideSendableInstantiatorRefersTo() async throws {
		// As above, with no seam: `Root` builds `Alpha` through a plain `alphaBuilder`, which the cycle closing inside
		// `Beta`'s `SendableInstantiator` makes `@Sendable`.
		let types = Self.sendableCycleDeclarations + [
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let credential: Credential", "@Instantiated let alphaBuilder: Instantiator<Alpha>"]),
		]
		let report = try await Self.report(ofRoot: "Root") {
			try await executeSafeDIToolTest(swiftFileContent: types, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(Self.nodeSendability(of: report) == [
			"Root: column false, tree false",
			"Credential as credential: Credential: column false, tree false",
			"Alpha as alphaBuilder: Instantiator<Alpha>: column true, tree true, refused cycleEnteredAtAnotherNode",
			"Beta as betaBuilder: SendableInstantiator<Beta>: column true, tree true",
		])
		#expect(TypeFactsChecks.findings(of: report).findingsByCheck[40] == nil)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func typeFacts_foldsNodeSendabilityInWorkLinearInChain_whenEachMadeSendableBuilderClosesCycleOnTheOneAbove() async throws {
		// `Link0` to `Link<n-1>` build each other in a chain of plain `Instantiator`s, each closing a cycle on the one above,
		// and the last builds `Tail` in a `SendableInstantiator`, whose cycle on the last makes its function `@Sendable`,
		// which makes the one above `@Sendable`, and so on up the chain: each node is finished once, each edge visited once
		// and each closed cycle judged once, so the fold's work grows with n. A judgment per path, or a cycle judged again
		// at each `@Sendable` function above it, would grow with n². Every link is in the cycle `Tail`'s
		// `SendableInstantiator` opens, so the fold refuses each link's column, which the tree's places all agree with.
		var work = [Int]()
		for length in [8, 32] {
			var types = [seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let link0Builder: Instantiator<Link0>"])]
			for index in 0..<length {
				var declarations = index > 0 ? ["@Instantiated let link\(index - 1)Builder: Instantiator<Link\(index - 1)>"] : []
				declarations.append(index + 1 < length ? "@Instantiated let link\(index + 1)Builder: Instantiator<Link\(index + 1)>" : "@Instantiated let tailBuilder: SendableInstantiator<Tail>")
				types.append(seamFixtureType(named: "Link\(index)", isFinalClass: true, declarations: declarations))
			}
			types.append(seamFixtureType(named: "Tail", isFinalClass: true, declarations: ["@Instantiated let link\(length - 1)Builder: Instantiator<Link\(length - 1)>"]))
			let (stream, continuation) = AsyncStream.makeStream(of: GenerationWork.self)
			let report = try await GenerationWork.$observer.withValue({ continuation.yield($0) }) {
				try await Self.report(ofRoot: "Root") {
					try await executeSafeDIToolTest(swiftFileContent: types, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete, skipCompileVerification: length != 8)
				}
			}
			continuation.finish()
			var count = 0
			for await step in stream where step.step == .foldingFillSendability {
				count += step.elementCount
			}
			work.append(count)
			let links = (0..<length).map { "Link\($0) as link\($0)Builder: Instantiator<Link\($0)>: column true, tree true, refused cycleEnteredAtAnotherNode" }
			#expect(Self.nodeSendability(of: report) == ["Root: column false, tree false"] + links + ["Tail as tailBuilder: SendableInstantiator<Tail>: column true, tree true"])
			#expect(TypeFactsChecks.findings(of: report).findingsByCheck[40] == nil)
		}
		// Each run folds the world twice, for the generator and for the report: per fold, the walk's 17 and 65 edges,
		// closings and keys (58 and 226), and the components' pass over the nodes on a cycle (9 and 33, every node but
		// `Root`) and their 16 and 64 edges (25 and 97). Each is linear in the chain: 646 is 3.9 times 166.
		#expect(work == [166, 646])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func typeFacts_refusesNodeColumn_whenCycleHoldingSendableInstantiatorIsEnteredAtTwoOfItsNodes() async throws {
		// `Root` enters the cycle of `Alpha`, `Beta` and `Sender` at `Alpha` and at `Beta`. Entered at `Alpha`, `Sender`'s
		// `@Sendable` function closes the cycle on `Alpha`, which it makes `@Sendable`; entered at `Beta`, it builds `Alpha`
		// again, which closes the cycle on `Beta`, which it makes `@Sendable` instead. Each of the two is `@Sendable` at one
		// of its places and not at the other, so the fold refuses both columns; `Sender` opens its own `@Sendable` function,
		// so its column is exact.
		let types = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let alphaBuilder: Instantiator<Alpha>", "@Instantiated let betaBuilder: Instantiator<Beta>"]),
			seamFixtureType(named: "Alpha", isFinalClass: true, declarations: ["@Instantiated let betaBuilder: Instantiator<Beta>"]),
			seamFixtureType(named: "Beta", isFinalClass: true, declarations: ["@Instantiated let senderBuilder: SendableInstantiator<Sender>"]),
			seamFixtureType(named: "Sender", isFinalClass: true, declarations: ["@Instantiated let alphaBuilder: Instantiator<Alpha>"]),
		]
		let report = try await Self.report(ofRoot: "Root") {
			try await executeSafeDIToolTest(swiftFileContent: types, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(Self.nodeSendability(of: report) == [
			"Root: column false, tree false",
			"Alpha as alphaBuilder: Instantiator<Alpha>: column true, tree false and true, refused cycleEnteredAtAnotherNode",
			"Beta as betaBuilder: Instantiator<Beta>: column false, tree false and true, refused cycleEnteredAtAnotherNode",
			"Sender as senderBuilder: SendableInstantiator<Sender>: column true, tree true",
		])
		let result = TypeFactsChecks.findings(of: report)
		#expect(result.findingsByCheck[40] == nil)
		// The two places each of `Alpha` and `Beta` has that close no cycle.
		#expect(result.refusedByCheck[40] == ["cycleEnteredAtAnotherNode": 4])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func typeFacts_refusesNodeAndFillColumns_whenEdgeReachesFinishedNodeOfCycleHoldingSendableInstantiator() async throws {
		// `Loop` builds `Inner` through `Relay` and again itself, in a cycle that `Sender`'s `SendableInstantiator` closes
		// on `Loop`: the fold finishes `Inner` from the first edge, and its second edge into `Inner` hands on none of the
		// cycles closed beneath it, so the fold refuses the columns of `Loop`, `Relay` and `Inner` with both refusals.
		// `Loop`'s call of `SubB` refers to `second`, whose fill column then depends on whether `Loop`'s function is
		// `@Sendable`, so it is refused too.
		let (edges, nodes) = try await fillEdges(
			defaultFirstDeclarations: ["@Instantiated let loopBuilder: Instantiator<Loop>"],
			middleTypes: [
				seamFixtureType(named: "Loop", declarations: ["@Instantiated let relayBuilder: Instantiator<Relay>", "@Instantiated let innerBuilder: Instantiator<Inner>", "@Instantiated let subB: SubB"]),
				seamFixtureType(named: "Relay", declarations: ["@Instantiated let innerBuilder: Instantiator<Inner>"]),
				seamFixtureType(named: "Inner", declarations: ["@Instantiated let senderBuilder: SendableInstantiator<Sender>"]),
				seamFixtureType(named: "Sender", declarations: ["@Instantiated let loopBuilder: Instantiator<Loop>"]),
			],
		)

		#expect(nodes == [
			"Host: column false, tree false",
			"Top as top: Top: column false, tree false",
			"DefaultFirst as first: any First fill: column false, tree false",
			"Loop as loopBuilder: Instantiator<Loop>: column true, tree true, refused cycleEnteredAtAnotherNode and closingsBeneathFinishedNode",
			"Relay as relayBuilder: Instantiator<Relay>: column false, tree false, refused cycleEnteredAtAnotherNode and closingsBeneathFinishedNode",
			"Inner as innerBuilder: Instantiator<Inner>: column false, tree false, refused cycleEnteredAtAnotherNode and closingsBeneathFinishedNode",
			"Sender as senderBuilder: SendableInstantiator<Sender>: column true, tree true",
			"SubB as subB: SubB: column false, tree false",
			"DefaultSecond as second: any Second fill: column false, tree false",
		])
		#expect(edges == [
			"Top as top: Top -> DefaultFirst as first: any First fill: column false, hole false, tree false",
			"Top as top: Top -> DefaultSecond as second: any Second fill: column true, hole false, tree true, refused dependsOnRefusedNode",
			"SubB as subB: SubB -> DefaultSecond as second: any Second fill: column true, hole false, tree true, refused dependsOnRefusedNode",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func typeFacts_refusesFillColumn_whenFillWhoseColumnIsRefusedRefersToIt() async throws {
		// `Loop`, in the cycle `Inner`'s `SendableInstantiator` opens, builds `SubA` again, which refers to `first`, so the
		// fold refuses `first`'s column. `DefaultFirst` builds `SubB` outside the cycle, which refers to `second` from
		// `first`'s fill: whether `second` builds in a `@Sendable` function follows whether `first` does, so the fold
		// refuses `second`'s column too, though no refused node refers to it.
		let (edges, nodes) = try await fillEdges(
			defaultFirstDeclarations: ["@Instantiated let loopBuilder: Instantiator<Loop>", "@Instantiated let subB: SubB"],
			middleTypes: [
				seamFixtureType(named: "Loop", declarations: ["@Instantiated let innerBuilder: SendableInstantiator<Inner>", "@Instantiated let subA: SubA"]),
				seamFixtureType(named: "Inner", declarations: ["@Instantiated let loopBuilder: Instantiator<Loop>"]),
			],
		)

		#expect(nodes == [
			"Host: column false, tree false",
			"Top as top: Top: column false, tree false",
			"DefaultFirst as first: any First fill: column false, tree false",
			"Loop as loopBuilder: Instantiator<Loop>: column true, tree true, refused cycleEnteredAtAnotherNode",
			"Inner as innerBuilder: SendableInstantiator<Inner>: column true, tree true",
			"SubA as subA: SubA: column false, tree false",
			"SubB as subB: SubB: column false, tree false",
			"DefaultSecond as second: any Second fill: column false, tree false",
		])
		#expect(edges == [
			"Top as top: Top -> DefaultFirst as first: any First fill: column true, hole false, tree true, refused dependsOnRefusedNode",
			"Top as top: Top -> DefaultSecond as second: any Second fill: column true, hole false, tree true, refused dependsOnRefusedNode",
			"SubA as subA: SubA -> DefaultFirst as first: any First fill: column true, hole false, tree true, refused dependsOnRefusedNode",
			"SubB as subB: SubB -> DefaultSecond as second: any Second fill: column true, hole false, tree true, refused dependsOnRefusedNode",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func typeFacts_refusesNoColumn_whenCycleEnteredAtTwoOfItsNodesOpensNoSendableFunction() async throws {
		// As the cycle entered at `Alpha` and at `Beta` above, with a plain `Instantiator` in `Sender`'s place: no function of
		// the cycle is `@Sendable`, so no closing makes one `@Sendable`, and every column is exact.
		let types = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let alphaBuilder: Instantiator<Alpha>", "@Instantiated let betaBuilder: Instantiator<Beta>"]),
			seamFixtureType(named: "Alpha", isFinalClass: true, declarations: ["@Instantiated let betaBuilder: Instantiator<Beta>"]),
			seamFixtureType(named: "Beta", isFinalClass: true, declarations: ["@Instantiated let senderBuilder: Instantiator<Sender>"]),
			seamFixtureType(named: "Sender", isFinalClass: true, declarations: ["@Instantiated let alphaBuilder: Instantiator<Alpha>"]),
		]
		let report = try await Self.report(ofRoot: "Root") {
			try await executeSafeDIToolTest(swiftFileContent: types, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(Self.nodeSendability(of: report) == [
			"Root: column false, tree false",
			"Alpha as alphaBuilder: Instantiator<Alpha>: column false, tree false",
			"Beta as betaBuilder: Instantiator<Beta>: column false, tree false",
			"Sender as senderBuilder: Instantiator<Sender>: column false, tree false",
		])
		let result = TypeFactsChecks.findings(of: report)
		#expect(result.findingsByCheck[40] == nil)
		#expect(result.refusedByCheck[40] == nil)
	}

	// MARK: Private

	/// `Alpha`, which receives `credential` and builds `Beta` in a `SendableInstantiator`; `Beta` declares `credential`
	/// and builds `Alpha` again through `alphaBuilder`, closing a cycle on the function that built it.
	private static let sendableCycleDeclarations = [
		"""
		@Instantiable
		public final class Alpha: Instantiable, Sendable {
		    public init(credential: Credential, betaBuilder: SendableInstantiator<Beta>) { self.credential = credential; self.betaBuilder = betaBuilder }
		    @Received public let credential: Credential
		    @Instantiated public let betaBuilder: SendableInstantiator<Beta>
		}
		""",
		"""
		@Instantiable
		public final class Beta: Instantiable {
		    public init(credential: Credential, alphaBuilder: Instantiator<Alpha>) { self.credential = credential; self.alphaBuilder = alphaBuilder }
		    @Instantiated public let credential: Credential
		    @Instantiated public let alphaBuilder: Instantiator<Alpha>
		}
		""",
		"""
		@Instantiable
		public final class Credential: Instantiable, Sendable {
		    public init() {}
		}
		""",
	]

	/// The report of the whole production tree of `root` the memo oracle observes while `generate` runs.
	private static func report(ofRoot root: String, generate: () async throws -> some Any) async throws -> TypeFactsReport {
		let (stream, continuation) = AsyncStream.makeStream(of: TypeFactsReport.self)
		_ = try await ConstructionMemoOracle.$observer.withValue({ _, _, report in continuation.yield(report) }, operation: generate)
		continuation.finish()
		var reports = [TypeFactsReport]()
		for await report in stream where report.root == root && !report.forMockGeneration {
			reports.append(report)
		}
		// The memo oracle observes a tree of the root for each body generated from it; the whole tree has the most places.
		return try #require(reports.max { $0.places.count < $1.places.count })
	}

	/// Each node that is no leaf, in node order: the column, what the tree decided at its places that close no cycle, and
	/// the fold's refusals of the column, where it has any.
	private static func nodeSendability(of report: TypeFactsReport) -> [String] {
		var treeByNode = [Int: Set<Bool>]()
		for place in report.places where !place.closesCycle {
			if let node = place.node, let generator = place.generator {
				treeByNode[node, default: []].insert(generator.buildsInSendableFunction)
			}
		}
		return report.nodes.enumerated().filter { !$0.element.isLeaf }.map { index, node in
			let tree = (treeByNode[index] ?? []).sorted { !$0 && $1 }.map(String.init).joined(separator: " and ")
			let refusal = node.sendabilityRefusal.isEmpty ? "" : ", refused \(node.sendabilityRefusal.joined(separator: " and "))"
			return "\(node.description): column \(node.buildsInSendableFunction), tree \(tree)\(refusal)"
		}
	}

	private var filesToDelete: [URL]

	/// Each fill edge of `Host`'s per-type facts, in node and edge order: its source and target, the column, whether the
	/// seam takes the fill `@Sendable`, what the tree decided at the places of its fill, and the fold's refusals of the
	/// column, where it has any; and each node of the report, as `nodeSendability(of:)` spells it. Checks 37 and 40 find
	/// nothing outside a refusal.
	private mutating func fillEdges(defaultFirstDeclarations: [String], middleTypes: [String]) async throws -> (edges: [String], nodes: [String]) {
		let modules = [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol First {}",
				"public protocol Second {}",
				seamFixtureType(named: "SubA", isSeam: true, declarations: ["@Instantiated let first: any First"]),
				seamFixtureType(named: "SubB", isSeam: true, declarations: ["@Instantiated let second: any Second"]),
				seamFixtureType(named: "Top", isSeam: true, declarations: ["@Instantiated let subA: SubA", "@Instantiated let subB: SubB"]),
			]),
			ModuleFixture(name: "Middle", packageName: "Mid", swiftFileContent: (middleTypes + [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultFirst", fulfilling: "First", declarations: defaultFirstDeclarations),
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultSecond", fulfilling: "Second", declarations: []),
				seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated let top: Top"]),
			]).map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let host: Host"])].map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
		]
		let (stream, continuation) = AsyncStream.makeStream(of: TypeFactsReport.self)
		_ = try await ConstructionMemoOracle.$observer.withValue({ _, _, report in continuation.yield(report) }) {
			try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
		continuation.finish()
		var reports = [TypeFactsReport]()
		for await report in stream where report.root == "Host" && !report.forMockGeneration {
			reports.append(report)
		}
		let report = try #require(reports.last)
		let findings = TypeFactsChecks.findings(of: report).findingsByCheck
		#expect(findings[37] == nil)
		#expect(findings[40] == nil)
		var treeByKey = [String: Set<Bool>]()
		for place in report.places {
			if let fillKey = place.fillKey, let buildsInSendableFunction = place.fillBuildsInSendableFunction {
				treeByKey[fillKey, default: []].insert(buildsInSendableFunction)
			}
		}
		var lines = [String]()
		for node in report.nodes {
			for (target, edge) in zip(node.edges, node.edgeFacts) where edge.isFill {
				let tree = (edge.fillKey.flatMap { treeByKey[$0] } ?? []).sorted { !$0 && $1 }.map(String.init).joined(separator: " and ")
				let refusal = edge.fillSendabilityRefusal.isEmpty ? "" : ", refused \(edge.fillSendabilityRefusal.joined(separator: " and "))"
				lines.append("\(node.description) -> \(report.nodes[target].description): column \(edge.fillBuildsInSendableFunction), hole \(edge.fillHoleIsSendable), tree \(tree)\(refusal)")
			}
		}
		return (edges: lines, nodes: Self.nodeSendability(of: report))
	}
}
