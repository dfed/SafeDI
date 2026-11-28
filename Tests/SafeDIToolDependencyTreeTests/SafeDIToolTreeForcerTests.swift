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
		Looping\tkind cycleReceivesBuilder
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
		Looping\tkind cycleReceivesBuilder, DOT graph
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
	mutating func generate_laysOutRoot_whenRootHasNoDependencies() async throws {
		// A root with no dependencies has no generated initializer, which the engine lays out from its records as the tree
		// writes it. `generate_buildsTree_whenRenameKeepingItsLabelReadsRenameKeepingItsLabelAbove` is a root the engine
		// cannot lay out yet.
		let (forcers, _) = try await treeForcers(of: [
			"""
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init() {}
			}
			""",
		])
		#expect(forcers == """
		Root\tnone
		roots that built a tree: 0 of 1

		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutRoot_whenRenameOfSharedTypeIsFulfilledByWrapperOnFirstPathAndValueOnSecond() async throws {
		let (forcers, _) = try await treeForcers(of: Self.renameFulfilledByWrapperAndValue(lazyParentFirst: true))
		// The rename beneath both parents keys its read of `x` by the form that answers it, so it has a variant beneath each,
		// and each variant's record binds it as its own key says: `x.instance` beneath `LazyParent`, `x` beneath `Holder`.
		// Every test compares the records' code with the tree's (`NodeRecordsChecks`).
		#expect(forcers == """
		Root\tnone
		roots that built a tree: 0 of 1

		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutRoot_whenRenameOfSharedTypeIsFulfilledByValueOnFirstPathAndWrapperOnSecond() async throws {
		let (forcers, _) = try await treeForcers(of: Self.renameFulfilledByWrapperAndValue(lazyParentFirst: false))
		// The same world with the root's properties swapped: which record each variant gets does not follow which parent is
		// declared first.
		#expect(forcers == """
		Root\tnone
		roots that built a tree: 0 of 1

		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutRoot_whenRenameKeepingItsLabelReadsInstanceOfLazilyInstantiatedPropertyAbove() async throws {
		// `Settings` renames `analytics` under its own label, so its scope binds the label the rename reads: the rename's
		// key names the wrapper above, which its record reads the instance of, as the tree does.
		let (forcers, _) = try await treeForcers(of: Self.keepLabelRenames(nestedRename: false))
		#expect(forcers == """
		Root\tnone
		roots that built a tree: 0 of 1

		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutRoot_whenRenameKeepingItsLabelReadsRenameKeepingItsLabelAbove() async throws {
		// `Detail`, beneath `Settings`, renames `analytics` under its own label too: its key names `Settings`' rename, the
		// nearest declaration, never the wrapper above `Settings`, so its record matches the tree's code
		// (`NodeRecordsChecks`), and the engine lays the root out, the rename read before its binding as one from outside.
		let (forcers, _) = try await treeForcers(of: Self.keepLabelRenames(nestedRename: true))
		#expect(forcers == """
		Root\tnone
		roots that built a tree: 0 of 1

		""")
	}

	@Test(arguments: [
		(analyticsType: "Analytics", analyticsFirst: true),
		(analyticsType: "Analytics", analyticsFirst: false),
		(analyticsType: "LazilyInstantiated<Analytics>", analyticsFirst: true),
		(analyticsType: "LazilyInstantiated<Analytics>", analyticsFirst: false),
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutRoot_whenRenameKeepingItsLabelOnlyIfAvailableReadsDeclarationAbove(analyticsType: String, analyticsFirst: Bool) async throws {
		// `Settings` renames `analytics` only if available under its own label: its optional reads of the label reach past
		// its scope's own binding to the value or the wrapper above, whichever the root declares first, as the tree reads it.
		let (forcers, _) = try await treeForcers(of: Self.keepLabelRenames(nestedRename: false, analyticsType: analyticsType, analyticsFirst: analyticsFirst, onlyIfAvailable: true))
		#expect(forcers == """
		Root\tnone
		roots that built a tree: 0 of 1

		""")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Plain`, a root node records lay out, and `Looping`, a root they refuse, since a type of its tree builds itself
	/// again through an `Instantiator` that a type beneath it receives.
	private static let plainAndLoopingRoots = [
		seamFixtureType(named: "Looping", isRoot: true, declarations: ["@Instantiated let stepBuilder: Instantiator<Step>"]),
		seamFixtureType(named: "Plain", isRoot: true, declarations: ["@Instantiated let service: Service"]),
		seamFixtureType(named: "Step", declarations: ["@Instantiated let stepBuilder: Instantiator<Step>", "@Instantiated let detail: Detail"]),
		seamFixtureType(named: "Detail", declarations: ["@Received let stepBuilder: Instantiator<Step>"]),
		seamFixtureType(named: "Service", declarations: []),
	]

	/// A root that instantiates `analytics` as a `LazilyInstantiated<Analytics>` and builds `Settings`, which renames it under
	/// its own label as an `EventTracker`; with `nestedRename`, `Settings` builds `Detail`, which renames `Settings`' rename
	/// under the same label as an `AnyTracker`. `analyticsType` is the type the root instantiates `analytics` as,
	/// `analyticsFirst` orders the root's two properties, and `onlyIfAvailable` makes `Settings`' rename one only if available.
	private static func keepLabelRenames(nestedRename: Bool, analyticsType: String = "LazilyInstantiated<Analytics>", analyticsFirst: Bool = true, onlyIfAvailable: Bool = false) -> [String] {
		let rootProperties = ["@Instantiated let analytics: \(analyticsType)", "@Instantiated let settingsBuilder: Instantiator<Settings>"]
		var files = [
			"""
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(analytics: \(analyticsType), settingsBuilder: Instantiator<Settings>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    \((analyticsFirst ? rootProperties : rootProperties.reversed()).joined(separator: "\n    "))
			}
			""",
			"""
			public protocol EventTracker {}

			@Instantiable
			public final class Analytics: EventTracker, Instantiable {
			    public init() {}
			}
			""",
		]
		if nestedRename {
			files.append("""
			@Instantiable
			public final class Settings: Instantiable {
			    public init(analytics: EventTracker, detail: Detail) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Received(fulfilledByDependencyNamed: "analytics", ofType: Analytics.self) let analytics: EventTracker
			    @Instantiated let detail: Detail
			}
			""")
			files.append("""
			public struct AnyTracker: EventTracker {
			    public init(_ tracker: EventTracker) {}
			}

			@Instantiable
			public final class Detail: Instantiable {
			    public init(analytics: AnyTracker) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Received(fulfilledByDependencyNamed: "analytics", ofType: EventTracker.self, erasedToConcreteExistential: true) let analytics: AnyTracker
			}
			""")
		} else {
			files.append("""
			@Instantiable
			public final class Settings: Instantiable {
			    public init(analytics: EventTracker\(onlyIfAvailable ? "?" : "")) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Received(fulfilledByDependencyNamed: "analytics", ofType: Analytics.self\(onlyIfAvailable ? ", onlyIfAvailable: true" : "")) let analytics: EventTracker\(onlyIfAvailable ? "?" : "")
			}
			""")
		}
		return files
	}

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
