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
/// the tree of, builds none, and `--tree-forcers-output` lists, for each root and seam, what made the run build its tree.
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
	mutating func generate_buildsEveryTree_whenModuleHoldsSeam() async throws {
		let (forcers, _) = try await treeForcers(
			of: [
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let screen: Screen"]),
				seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Instantiated let service: Service"]),
				seamFixtureType(named: "Service", declarations: []),
			],
			moduleMembershipArguments: ["--module-name", "Feature"],
		)
		// Node records make the records of the root's world, which calls the seam, and of the seam's own world.
		#expect(forcers == """
		Root\tseam world
		Screen\tseam world
		roots that built a tree: 2 of 2

		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsTree_whenRecordsOfRootCannotBeLaidOut() async throws {
		// `C` declares `y` as an alias of `S`'s forwarded `x` only if available, beside `S`'s own `y`, and `D` beneath `C` receives
		// `y`. A read of `D`'s laid out by type resolves at its place to another declaration than its view's, so the engine refuses
		// the root's records and the root keeps its tree.
		let (forcers, _) = try await treeForcers(of: [
			"""
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(sBuilder: Instantiator<S>) { self.sBuilder = sBuilder }
			    @Instantiated let sBuilder: Instantiator<S>
			}
			""",
			"""
			@Instantiable
			public final class S: Instantiable {
			    public init(x: X, b: B, y: X) { self.x = x; self.b = b; self.y = y }
			    @Forwarded let x: X
			    @Instantiated let b: B
			    @Instantiated let y: X
			}
			""",
			"""
			@Instantiable
			public final class X: Instantiable {
			    public init(b: B) { self.b = b }
			    @Received let b: B
			}
			""",
			"""
			@Instantiable
			public final class B: Instantiable {
			    public init(c: C) { self.c = c }
			    @Instantiated let c: C
			}
			""",
			"""
			@Instantiable
			public final class C: Instantiable {
			    public init(y: X?, d: D) { self.y = y; self.d = d }
			    @Received(fulfilledByDependencyNamed: "x", ofType: X?.self, onlyIfAvailable: true) let y: X?
			    @Instantiated let d: D
			}
			""",
			"""
			@Instantiable
			public final class D: Instantiable {
			    public init(y: X?) { self.y = y }
			    @Received let y: X?
			}
			""",
		])
		#expect(forcers == """
		Root\tkind notLaidOut
		roots that built a tree: 1 of 1

		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsTree_whenRenameOfSharedTypeIsFulfilledByWrapperOnFirstPathAndValueOnSecond() async throws {
		let (forcers, _) = try await treeForcers(of: Self.renameFulfilledByWrapperAndValue(lazyParentFirst: true))
		// One variant of `Reader`'s rename is called beneath both parents, which answer its `x` as a wrapper's instance and as
		// a value: its one record would be wrong beneath one of them.
		#expect(forcers == """
		Root\tkind callsAnswerAVariantApart
		roots that built a tree: 1 of 1

		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsTree_whenRenameOfSharedTypeIsFulfilledByValueOnFirstPathAndWrapperOnSecond() async throws {
		let (forcers, _) = try await treeForcers(of: Self.renameFulfilledByWrapperAndValue(lazyParentFirst: false))
		// The same world with the root's properties swapped: the refusal does not follow which parent is declared first.
		#expect(forcers == """
		Root\tkind callsAnswerAVariantApart
		roots that built a tree: 1 of 1

		""")
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

	/// A root whose two parents each build a `Reader` whose rename is fulfilled by `x`: `LazyParent` declares `x` as a
	/// `LazilyInstantiated<X>` and builds `Reader` through an `Instantiator`, and `ValueParent` declares `x` as an `X`
	/// and builds `Reader` beneath `Holder`. `lazyParentFirst` orders the root's two properties.
	private static func renameFulfilledByWrapperAndValue(lazyParentFirst: Bool) -> [String] {
		let parents = ["@Instantiated let lazyParent: LazyParent", "@Instantiated let valueParent: ValueParent"]
		return [
			seamFixtureType(named: "Root", isRoot: true, declarations: lazyParentFirst ? parents : parents.reversed()),
			seamFixtureType(named: "LazyParent", declarations: ["@Instantiated let readerBuilder: Instantiator<Reader>", "@Instantiated let x: LazilyInstantiated<X>"]),
			seamFixtureType(named: "ValueParent", declarations: ["@Instantiated let x: X", "@Instantiated let holder: Holder"]),
			seamFixtureType(named: "Holder", declarations: ["@Instantiated let reader: Reader"]),
			seamFixtureType(named: "Reader", declarations: [#"@Received(fulfilledByDependencyNamed: "x", ofType: X.self) let renamed: X"#]),
			seamFixtureType(named: "X", declarations: []),
		]
	}

	/// What `--tree-forcers-output` holds once `files` are generated, and the code tasks each tree the run built still
	/// held once its code was planned, in the order the trees were counted.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func treeForcers(of files: [String], buildDOTFileOutput: Bool = false, moduleMembershipArguments: [String] = []) async throws -> (forcers: String, heldTaskCounts: [Int]) {
		let output = TestTemporaryDirectory.uniquePath(prefix: "TreeForcers", pathExtension: "txt")
		filesToDelete.append(output)
		let (stream, continuation) = AsyncStream.makeStream(of: Int.self)
		_ = try await HeldCodeTasks.$observer.withValue({ continuation.yield($0) }) {
			try await executeSafeDIToolTest(
				swiftFileContent: files,
				buildSwiftOutputDirectory: true,
				buildDOTFileOutput: buildDOTFileOutput,
				filesToDelete: &filesToDelete,
				moduleMembershipArguments: moduleMembershipArguments,
				treeForcersOutput: output,
			)
		}
		continuation.finish()
		var heldTaskCounts = [Int]()
		for await count in stream {
			heldTaskCounts.append(count)
		}
		return (try String(contentsOf: output, encoding: .utf8), heldTaskCounts)
	}
}
