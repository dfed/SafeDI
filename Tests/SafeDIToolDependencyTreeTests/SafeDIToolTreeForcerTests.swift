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

/// What makes `generate` build a root's place tree (`TreeForcer`): a root node records lay out, which nothing else reads
/// the tree of, builds none, a root of a module with seams that is none of its own seams included, and
/// `--tree-forcers-output` lists, for each root and seam, what made the run build its tree.
struct SafeDIToolTreeForcerTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsTreeOnlyForRootNodeRecordsRefuse_whenNothingElseReadsTrees() async throws {
		let (forcers, heldTaskCounts) = try await treeForcers(of: Self.plainAndLoopingRoots)
		#expect(forcers == """
		Looping\tkind cycle
		Plain\tnone
		roots that built a tree: 1 of 2

		""")
		// A tree's code tasks are counted once its code is planned: only `Looping` built one.
		#expect(heldTaskCounts == [0])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsEveryRootsTree_whenRunDrawsDOTGraph() async throws {
		let (forcers, heldTaskCounts) = try await treeForcers(of: Self.plainAndLoopingRoots, buildDOTFileOutput: true)
		#expect(forcers == """
		Looping\tkind cycle, DOT graph
		Plain\tDOT graph
		roots that built a tree: 2 of 2

		""")
		#expect(heldTaskCounts == [0, 0])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsTreeOnlyForOwnSeam_whenNothingForcesAppRootsTree() async throws {
		// A plain run, with the switch for modules without seams off: `Root`, which calls the module's own seam, is laid out
		// from its world's node records and builds no tree, while the seam's own root still builds its tree.
		let (forcers, _) = try await treeForcers(of: Self.rootCallingOwnSeam(rootDeclarations: []), buildsNoTreeForAcceptedRoots: false, moduleMembershipArguments: ["--module-name", "Feature"])
		#expect(forcers == """
		Root\tnone
		Screen\tseam world
		roots that built a tree: 1 of 2

		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsAppRootsTree_whenModuleHoldsSeamAndRunDrawsDOTGraph() async throws {
		let (forcers, _) = try await treeForcers(of: Self.rootCallingOwnSeam(rootDeclarations: []), buildDOTFileOutput: true, buildsNoTreeForAcceptedRoots: false, moduleMembershipArguments: ["--module-name", "Feature"])
		#expect(forcers == """
		Root\tDOT graph
		Screen\tseam world
		roots that built a tree: 2 of 2

		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsAppRootsTree_whenModuleHoldsSeamAndNodeRecordsRefuseRootsWorld() async throws {
		// `Root`'s tree builds `Step` again through an `Instantiator`, a cycle node records do not make.
		let (forcers, _) = try await treeForcers(
			of: Self.rootCallingOwnSeam(rootDeclarations: ["@Instantiated let stepBuilder: Instantiator<Step>"]) + [
				seamFixtureType(named: "Step", declarations: ["@Instantiated let stepBuilder: Instantiator<Step>"]),
			],
			buildsNoTreeForAcceptedRoots: false,
			moduleMembershipArguments: ["--module-name", "Feature"],
		)
		#expect(forcers == """
		Root\tkind cycle
		Screen\tseam world
		roots that built a tree: 2 of 2

		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsAppRootsTree_whenRootsSeamCallDefersParameterSendable() async throws {
		// `Screen`'s `Panel`, built in a `SendableInstantiator`'s `@Sendable` function, receives `token`, so the seam defers
		// its pass-through `token` `@Sendable`, and the capture check reads `Root`'s call of it from `Root`'s tree.
		let (forcers, _) = try await treeForcers(
			of: [
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let token: Token", "@Instantiated let screen: Screen"]),
				seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Instantiated let panelBuilder: SendableInstantiator<Panel>"]),
				seamFixtureType(named: "Panel", declarations: ["@Received let token: Token"], conformances: ", Sendable"),
				seamFixtureType(named: "Token", declarations: [], conformances: ", Sendable"),
			],
			buildsNoTreeForAcceptedRoots: false,
			moduleMembershipArguments: ["--module-name", "Feature"],
		)
		#expect(forcers == """
		Root\tseam call defers a parameter @Sendable
		Screen\tseam world
		roots that built a tree: 2 of 2

		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsAppRootsTree_whenRootsSeamCallOmitsParameter() async throws {
		// `Library`'s `Panel`, whose `public` tier omits the `token` its `Badge` receives only if available, since `Token`
		// is internal: `App`'s call of that tier is one `validateNoSeamTierOmitsProvidedValue` judges from `Root`'s tree.
		let forcersByRoot = try await treeForcersReported(byModules: [
			ModuleFixture(
				name: "Library",
				packageName: "App",
				swiftFileContent: [
					seamFixtureType(named: "Panel", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
					"""
					@Instantiable
					public struct Badge: Instantiable {
					    init(token: Token?) {
					        self.token = token
					    }

					    @Received(onlyIfAvailable: true) let token: Token?
					}
					""",
					"""
					@Instantiable
					struct Token: Instantiable {
					    init() {}
					}
					""",
				],
				dependencies: [],
			),
			ModuleFixture(name: "Feature", packageName: "Other", swiftFileContent: [
				"import Library\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let panel: Panel"]),
			], dependencies: ["Library"]),
		])
		#expect(forcersByRoot["Root"] == ["seam call omits a parameter"])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Plain`, a root node records lay out, and `Looping`, a root they refuse, since a type of its tree builds itself
	/// again through an `Instantiator`.
	private static let plainAndLoopingRoots = [
		seamFixtureType(named: "Looping", isRoot: true, declarations: ["@Instantiated let stepBuilder: Instantiator<Step>"]),
		seamFixtureType(named: "Plain", isRoot: true, declarations: ["@Instantiated let service: Service"]),
		seamFixtureType(named: "Step", declarations: ["@Instantiated let stepBuilder: Instantiator<Step>"]),
		seamFixtureType(named: "Service", declarations: []),
	]

	/// `Root`, which builds `Screen`, a seam of its own module, beside `rootDeclarations`, and `Screen`'s `Service`.
	private static func rootCallingOwnSeam(rootDeclarations: [String]) -> [String] {
		[
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let screen: Screen"] + rootDeclarations),
			seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Instantiated let service: Service"]),
			seamFixtureType(named: "Service", declarations: []),
		]
	}

	/// What `--tree-forcers-output` holds once `files` are generated, and the code tasks each tree the run built still
	/// held once its code was planned, in the order the trees were counted. `buildsNoTreeForAcceptedRoots` turns on the
	/// switch to node records of a module without seams, as it is once it lands.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func treeForcers(of files: [String], buildDOTFileOutput: Bool = false, buildsNoTreeForAcceptedRoots: Bool = true, moduleMembershipArguments: [String] = []) async throws -> (forcers: String, heldTaskCounts: [Int]) {
		let output = TestTemporaryDirectory.uniquePath(prefix: "TreeForcers", pathExtension: "txt")
		filesToDelete.append(output)
		let (stream, continuation) = AsyncStream.makeStream(of: Int.self)
		_ = try await NodeRecordsObservation.$buildsNoTreeForAcceptedRoots.withValue(buildsNoTreeForAcceptedRoots) {
			try await HeldCodeTasks.$observer.withValue({ continuation.yield($0) }) {
				try await executeSafeDIToolTest(
					swiftFileContent: files,
					buildSwiftOutputDirectory: true,
					buildDOTFileOutput: buildDOTFileOutput,
					filesToDelete: &filesToDelete,
					moduleMembershipArguments: moduleMembershipArguments,
					treeForcersOutput: output,
				)
			}
		}
		continuation.finish()
		var heldTaskCounts = [Int]()
		for await count in stream {
			heldTaskCounts.append(count)
		}
		return (try String(contentsOf: output, encoding: .utf8), heldTaskCounts)
	}

	/// What made the run of each of `modules` build each root's tree, by root, as the node records report each root a run
	/// generates (`NodeRecordsReport.treeForcers`): empty for a root laid out from its node records alone.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func treeForcersReported(byModules modules: [ModuleFixture]) async throws -> [String: [String]] {
		let (stream, continuation) = AsyncStream.makeStream(of: NodeRecordsReport.self)
		_ = try await NodeRecordsObservation.$observer.withValue({ continuation.yield($0) }) {
			try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
		continuation.finish()
		var forcersByRoot = [String: [String]]()
		for await report in stream where !report.isMockRoot {
			forcersByRoot[report.root] = report.treeForcers.map(\.description)
		}
		return forcersByRoot
	}
}
