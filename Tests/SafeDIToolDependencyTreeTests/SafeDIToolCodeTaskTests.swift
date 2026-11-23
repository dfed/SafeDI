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

/// The tasks a dependency tree's scopes generate their code on. A task holds the async frames of its code, about 5 KB
/// each, until the task is released: when every scope's finished task stayed in its generator's cache, and every scope
/// started one, `generate` held about 13 KB for each line it generated, three times 2.2.0's peak memory. The tasks are
/// counted, not the memory, so that the checks are the same on every machine and every run.
struct SafeDIToolCodeTaskTests: ~Copyable {
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
	mutating func generate_holdsNoFinishedCodeTask_whenSeveralRootsBuildTreesOfSeveralLevels() async throws {
		// Two roots, each building four levels of three types, the two deepest through instantiators: 121 scopes each, so
		// each root and the three subtrees beneath it start their code early. Each starts it for the context its parent asks
		// in, so no task is still running once the code is done: with the release reverted, the trees hold one task for
		// each scope, 121 each.
		let fixture = Self.ternaryTree(depth: 4, beneath: ["FirstRoot", "SecondRoot"], rootDeclarations: [], instantiatesLayer: 3)
		let (stream, continuation) = AsyncStream.makeStream(of: Int.self)
		_ = try await HeldCodeTasks.$observer.withValue({ continuation.yield($0) }) {
			try await executeSafeDIToolTest(
				swiftFileContent: fixture,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				// The trees' code is what every other test of their shapes compares; this one counts how it is generated.
				skipCompileVerification: true,
			)
		}
		continuation.finish()
		var heldTaskCounts = [Int]()
		for await heldTaskCount in stream {
			heldTaskCounts.append(heldTaskCount)
		}
		// One count for each root's tree.
		#expect(heldTaskCounts == [0, 0])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_startsTasksForFewScopes_whenTreeHasManySmallSubtrees() async throws {
		let starts = try await countCodeTaskStarts(of: Self.ternaryTree(depth: Self.depth, beneath: ["Root"], rootDeclarations: []))
		// The root and the scopes of the next two levels, whose subtrees have 364 and 121 scopes, each on a task of its own,
		// and the subtrees of 40 scopes beneath them, in two groups, of 80 and 40. The construction memo shares one generator
		// between every place of a level that builds the same type in the same context, so each level holds three, which
		// start once: 1 + 3 + 3 + 2. Without the memo, 31; one task for each subtree of 40 as well, 40. Every scope of the
		// tree, one per path, started early: 1,093.
		#expect(starts == 9)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_startsOneTaskForEachGroupOfSmallSubtrees_whenRootHasManySmallSubtrees() async throws {
		// The root is a seam, since a root of the dependency tree starts no code early. It instantiates 30 children of three
		// scopes each, 91 scopes in all, so its subtree is large and each child's is small. The children start in groups of
		// at least 64 scopes: the first 22 (66 scopes) on one task and the last 8 on another, beside the root's own. One task
		// for each child, as before, ran 30 children's code together: 31.
		let children = (0..<30).map { "Child\($0)" }
		let fixture = [
			seamFixtureType(named: "Root", isSeam: true, isFinalClass: true, declarations: children.map { "@Instantiated let \($0.lowercased()): \($0)" }),
			seamFixtureType(named: "LeafA", isFinalClass: true, declarations: []),
			seamFixtureType(named: "LeafB", isFinalClass: true, declarations: []),
		] + children.map { child in
			seamFixtureType(named: child, isFinalClass: true, declarations: ["@Instantiated let leafA: LeafA", "@Instantiated let leafB: LeafB"])
		}
		let starts = try await countCodeTaskStarts(of: fixture)
		#expect(starts == 3)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_startsTasksForFewScopes_whenTreeIsCreatedAgainForItsLazyCycle() async throws {
		// The step builds a session of its own, which the screen it builds again receives: the tree is created a second time
		// with the parameter the screen's builder function takes. The seam's first signature pass settles it, so emission
		// makes that pass's tree again rather than creating it twice, and starts its code once: 10 tasks, the ternary tree's
		// 9 and one for the root's two other small subtrees, which group together. A tree emission created twice started 10
		// on each pass (32 each without the construction memo, and 42 with a task for each small subtree); every scope of
		// both passes started early, 2,196.
		let cycle = [
			seamFixtureType(named: "Screen", isFinalClass: true, declarations: ["@Received let session: Session", "@Instantiated let stepBuilder: Instantiator<Step>"]),
			seamFixtureType(named: "Step", isFinalClass: true, declarations: ["@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>"]),
			seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
		]
		let starts = try await countCodeTaskStarts(of: Self.ternaryTree(
			depth: Self.depth,
			beneath: ["Root"],
			rootDeclarations: ["@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>"],
		) + cycle)
		#expect(starts == 10)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_startsTasksForFewScopes_whenSeamThatTakesAParameterIsCreatedAgainForItsLazyCycle() async throws {
		// The tree of `generate_startsTasksForFewScopes_whenTreeIsCreatedAgainForItsLazyCycle`, whose screen also receives a
		// token nothing in the tree provides. The seam takes the token, so its first signature pass does not settle it, and
		// emission creates its tree anew: twice, for the lazy cycle. The second creation reuses each place the first built
		// settled, and starts again the groups the first started beneath it: 10 tasks on each creation, 20.
		let cycle = [
			seamFixtureType(named: "Screen", isFinalClass: true, declarations: ["@Received let session: Session", "@Received let token: Token", "@Instantiated let stepBuilder: Instantiator<Step>"]),
			seamFixtureType(named: "Step", isFinalClass: true, declarations: ["@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>"]),
			seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Token", isFinalClass: true, declarations: []),
		]
		let starts = try await countCodeTaskStarts(of: Self.ternaryTree(
			depth: Self.depth,
			beneath: ["Root"],
			rootDeclarations: ["@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>"],
		) + cycle)
		#expect(starts == 20)
	}

	@Test
	@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
	mutating func generate_writesSameCode_whenEarlyStartsFinishInAnyOrder() async throws {
		// The tree its lazy cycle has created twice starts 10 tasks early once emission makes it again, as
		// `generate_startsTasksForFewScopes_whenTreeIsCreatedAgainForItsLazyCycle` counts. Each run forces the order in which
		// they finish, and the code must be what a run whose starts race writes.
		let fixture = Self.ternaryTree(
			depth: Self.depth,
			beneath: ["Root"],
			rootDeclarations: ["@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>"],
		) + [
			seamFixtureType(named: "Screen", isFinalClass: true, declarations: ["@Received let session: Session", "@Instantiated let stepBuilder: Instantiator<Step>"]),
			seamFixtureType(named: "Step", isFinalClass: true, declarations: ["@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>"]),
			seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
		]
		let racing = try await executeSafeDIToolTest(
			swiftFileContent: fixture,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			// The tree's code is what every other test of its shapes compares; this one compares it across orders.
			skipCompileVerification: true,
		)
		var orders: [@Sendable (Int) -> [Int]] = [{ Array(0..<$0) }, { Array((0..<$0).reversed()) }]
		for seed in UInt64(1)...4 {
			orders.append { count in
				var state = seed
				return (0..<count).map { position in
					// SplitMix64.
					state &+= 0x9E3779B97F4A7C15
					var mixed = state
					mixed = (mixed ^ (mixed >> 30)) &* 0xBF58476D1CE4E5B9
					mixed = (mixed ^ (mixed >> 27)) &* 0x94D049BB133111EB
					return (key: mixed ^ (mixed >> 31), position: position)
				}
				.sorted { $0.key < $1.key }
				.map(\.position)
			}
		}
		for order in orders {
			let ordering = ForcedCodeTaskStartOrder(order: order)
			let ordered = try await CodeTaskStart.$ordering.withValue(ordering) {
				try await executeSafeDIToolTest(
					swiftFileContent: fixture,
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
					skipCompileVerification: true,
				)
			}
			// Every start took its turn in the order forced.
			#expect(await ordering.turnsTaken() == order(10))
			#expect(ordered.dependencyTreeFiles == racing.dependencyTreeFiles)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_startsNoTask_whenTypeKeyLaysOutTheRoot() async throws {
		// The tree of `generate_startsTasksForFewScopes_whenTreeHasManySmallSubtrees`, whose seam starts 10, beneath a root of
		// the dependency tree. The type key lays the root's body out from the plan of every place at the context the root asks
		// for, so the root starts none.
		let starts = try await countCodeTaskStarts(of: Self.ternaryTree(depth: Self.depth, beneath: ["Root"], rootDeclarations: [], asSeams: false))
		#expect(starts == 0)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesChildrenInTheirDeclarationOrder_whenTheirCodeIsPlannedAtOnce() async throws {
		// The root's six children are planned at once, four in flight at a time, and the larger ones are declared first, so
		// that their tasks tend to finish last. The body writes them in the order the root declares them, on every run,
		// whichever task finishes first.
		let fixture = Self.sixChildrenDeclaredLargestFirst
		for iteration in 0..<20 {
			let output = try await executeSafeDIToolTest(
				swiftFileContent: fixture,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				// One compile of the code checks it; every other run checks only the order.
				skipCompileVerification: iteration > 0,
			)
			#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			extension Root {
			    public convenience init() {
			        func __safeDI_child5() -> Child5 {
			            let leaf0 = Leaf0()
			            let leaf1 = Leaf1()
			            let leaf2 = Leaf2()
			            let leaf3 = Leaf3()
			            let leaf4 = Leaf4()
			            let leaf5 = Leaf5()
			            return Child5(leaf0: leaf0, leaf1: leaf1, leaf2: leaf2, leaf3: leaf3, leaf4: leaf4, leaf5: leaf5)
			        }
			        let child5: Child5 = __safeDI_child5()
			        func __safeDI_child2() -> Child2 {
			            let leaf0 = Leaf0()
			            let leaf1 = Leaf1()
			            let leaf2 = Leaf2()
			            return Child2(leaf0: leaf0, leaf1: leaf1, leaf2: leaf2)
			        }
			        let child2: Child2 = __safeDI_child2()
			        func __safeDI_child4() -> Child4 {
			            let leaf0 = Leaf0()
			            let leaf1 = Leaf1()
			            let leaf2 = Leaf2()
			            let leaf3 = Leaf3()
			            let leaf4 = Leaf4()
			            return Child4(leaf0: leaf0, leaf1: leaf1, leaf2: leaf2, leaf3: leaf3, leaf4: leaf4)
			        }
			        let child4: Child4 = __safeDI_child4()
			        func __safeDI_child0() -> Child0 {
			            let leaf0 = Leaf0()
			            return Child0(leaf0: leaf0)
			        }
			        let child0: Child0 = __safeDI_child0()
			        func __safeDI_child3() -> Child3 {
			            let leaf0 = Leaf0()
			            let leaf1 = Leaf1()
			            let leaf2 = Leaf2()
			            let leaf3 = Leaf3()
			            return Child3(leaf0: leaf0, leaf1: leaf1, leaf2: leaf2, leaf3: leaf3)
			        }
			        let child3: Child3 = __safeDI_child3()
			        func __safeDI_child1() -> Child1 {
			            let leaf0 = Leaf0()
			            let leaf1 = Leaf1()
			            return Child1(leaf0: leaf0, leaf1: leaf1)
			        }
			        let child1: Child1 = __safeDI_child1()
			        self.init(child5: child5, child2: child2, child4: child4, child0: child0, child3: child3, child1: child1)
			    }
			}
			""", "Unexpected output on run \(iteration) \(output.dependencyTreeFiles["Root+SafeDI.swift"] ?? "")")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_plansOnlyTheRootsChildrenAtOnce_whenATypeKeyRootStartsNoCodeEarly() async throws {
		// The root starts no code early, so its tree is planned once it exists, the root's six children at once, at most four
		// in flight. Each child plans its leaves one after another, so only the root's body reports.
		let (stream, continuation) = AsyncStream.makeStream(of: Int.self)
		_ = try await ConcurrentChildCode.$observer.withValue({ continuation.yield($0) }) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.sixChildrenDeclaredLargestFirst,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				// `generate_writesChildrenInTheirDeclarationOrder_whenTheirCodeIsPlannedAtOnce` compiles this tree's code.
				skipCompileVerification: true,
			)
		}
		continuation.finish()
		var childCounts = [Int]()
		for await childCount in stream {
			childCounts.append(childCount)
		}
		#expect(childCounts == [6])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// A root of the dependency tree whose six children, `Child0` to `Child5`, receive one to six leaves, declared in the
	/// order 5, 2, 4, 0, 3, 1.
	private static let sixChildrenDeclaredLargestFirst = [
		"""
		@Instantiable(isRoot: true)
		public final class Root: Instantiable {
		    public init(child5: Child5, child2: Child2, child4: Child4, child0: Child0, child3: Child3, child1: Child1) {
		        self.child5 = child5
		        self.child2 = child2
		        self.child4 = child4
		        self.child0 = child0
		        self.child3 = child3
		        self.child1 = child1
		    }

		    @Instantiated let child5: Child5
		    @Instantiated let child2: Child2
		    @Instantiated let child4: Child4
		    @Instantiated let child0: Child0
		    @Instantiated let child3: Child3
		    @Instantiated let child1: Child1
		}
		""",
		"""
		@Instantiable
		public final class Child0: Instantiable {
		    public init(leaf0: Leaf0) {
		        self.leaf0 = leaf0
		    }

		    @Instantiated let leaf0: Leaf0
		}
		""",
		"""
		@Instantiable
		public final class Child1: Instantiable {
		    public init(leaf0: Leaf0, leaf1: Leaf1) {
		        self.leaf0 = leaf0
		        self.leaf1 = leaf1
		    }

		    @Instantiated let leaf0: Leaf0
		    @Instantiated let leaf1: Leaf1
		}
		""",
		"""
		@Instantiable
		public final class Child2: Instantiable {
		    public init(leaf0: Leaf0, leaf1: Leaf1, leaf2: Leaf2) {
		        self.leaf0 = leaf0
		        self.leaf1 = leaf1
		        self.leaf2 = leaf2
		    }

		    @Instantiated let leaf0: Leaf0
		    @Instantiated let leaf1: Leaf1
		    @Instantiated let leaf2: Leaf2
		}
		""",
		"""
		@Instantiable
		public final class Child3: Instantiable {
		    public init(leaf0: Leaf0, leaf1: Leaf1, leaf2: Leaf2, leaf3: Leaf3) {
		        self.leaf0 = leaf0
		        self.leaf1 = leaf1
		        self.leaf2 = leaf2
		        self.leaf3 = leaf3
		    }

		    @Instantiated let leaf0: Leaf0
		    @Instantiated let leaf1: Leaf1
		    @Instantiated let leaf2: Leaf2
		    @Instantiated let leaf3: Leaf3
		}
		""",
		"""
		@Instantiable
		public final class Child4: Instantiable {
		    public init(leaf0: Leaf0, leaf1: Leaf1, leaf2: Leaf2, leaf3: Leaf3, leaf4: Leaf4) {
		        self.leaf0 = leaf0
		        self.leaf1 = leaf1
		        self.leaf2 = leaf2
		        self.leaf3 = leaf3
		        self.leaf4 = leaf4
		    }

		    @Instantiated let leaf0: Leaf0
		    @Instantiated let leaf1: Leaf1
		    @Instantiated let leaf2: Leaf2
		    @Instantiated let leaf3: Leaf3
		    @Instantiated let leaf4: Leaf4
		}
		""",
		"""
		@Instantiable
		public final class Child5: Instantiable {
		    public init(leaf0: Leaf0, leaf1: Leaf1, leaf2: Leaf2, leaf3: Leaf3, leaf4: Leaf4, leaf5: Leaf5) {
		        self.leaf0 = leaf0
		        self.leaf1 = leaf1
		        self.leaf2 = leaf2
		        self.leaf3 = leaf3
		        self.leaf4 = leaf4
		        self.leaf5 = leaf5
		    }

		    @Instantiated let leaf0: Leaf0
		    @Instantiated let leaf1: Leaf1
		    @Instantiated let leaf2: Leaf2
		    @Instantiated let leaf3: Leaf3
		    @Instantiated let leaf4: Leaf4
		    @Instantiated let leaf5: Leaf5
		}
		""",
		"""
		@Instantiable
		public final class Leaf0: Instantiable {
		    public init() {}
		}
		""",
		"""
		@Instantiable
		public final class Leaf1: Instantiable {
		    public init() {}
		}
		""",
		"""
		@Instantiable
		public final class Leaf2: Instantiable {
		    public init() {}
		}
		""",
		"""
		@Instantiable
		public final class Leaf3: Instantiable {
		    public init() {}
		}
		""",
		"""
		@Instantiable
		public final class Leaf4: Instantiable {
		    public init() {}
		}
		""",
		"""
		@Instantiable
		public final class Leaf5: Instantiable {
		    public init() {}
		}
		""",
	]

	/// The layers of types beneath the root of the trees whose early starts are counted: 1 + 3 + 9 + … + 3⁶ = 1,093
	/// scopes, one per path.
	private static let depth = 6

	/// `roots`, seams unless `asSeams` is `false`, since a root of the dependency tree starts no code early, and `depth`
	/// layers of three types each, `L<layer>A` to `L<layer>C`, each instantiating the three types of
	/// the layer beneath it, so that each root's tree has a scope for each of `3^layer` paths to each layer. The types of
	/// layer `instantiatesLayer` and below are instantiated through an `Instantiator`.
	private static func ternaryTree(depth: Int, beneath roots: [String], rootDeclarations: [String], instantiatesLayer: Int? = nil, asSeams: Bool = true) -> [String] {
		let letters = ["A", "B", "C"]
		func declarations(instantiatingLayer layer: Int) -> [String] {
			guard layer <= depth else { return [] }
			return letters.map { letter in
				if let instantiatesLayer, layer >= instantiatesLayer {
					"@Instantiated let l\(layer)\(letter.lowercased())Builder: Instantiator<L\(layer)\(letter)>"
				} else {
					"@Instantiated let l\(layer)\(letter.lowercased()): L\(layer)\(letter)"
				}
			}
		}
		var files = roots.map { root in
			seamFixtureType(named: root, isSeam: asSeams, isRoot: !asSeams, isFinalClass: true, declarations: rootDeclarations + declarations(instantiatingLayer: 1))
		}
		for layer in 1...depth {
			for letter in letters {
				files.append(seamFixtureType(named: "L\(layer)\(letter)", isFinalClass: true, declarations: declarations(instantiatingLayer: layer + 1)))
			}
		}
		return files
	}

	/// How many scopes started generating their code on a task of their own while `fixture` generated.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func countCodeTaskStarts(of fixture: [String]) async throws -> Int {
		let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
		_ = try await CodeTaskStart.$observer.withValue({ continuation.yield(()) }) {
			try await executeSafeDIToolTest(
				swiftFileContent: fixture,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				// The tree's code is what every other test of its shapes compares; this one counts how it is generated.
				skipCompileVerification: true,
			)
		}
		continuation.finish()
		var starts = 0
		for await _ in stream {
			starts += 1
		}
		return starts
	}
}
