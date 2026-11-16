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
		// The root and the 12 scopes of the next two levels, whose subtrees have 364 and 121 scopes, and the 27 subtrees of
		// 40 scopes beneath them. Every scope of the tree, one per path, started early: 1,093.
		#expect(starts == 40)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_startsTasksForFewScopes_whenTreeIsCreatedAgainForItsLazyCycle() async throws {
		// The step builds a session of its own, which the screen it builds again receives: the tree is created a second time
		// with the parameter the screen's builder function takes. The first pass starts its scopes' code as it creates them,
		// and the second once its tree exists: 42 each, the ternary tree's 40 and the root's two other small subtrees.
		// Every scope of both passes started early: 2,196.
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
		#expect(starts == 84)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The layers of types beneath the root of the trees whose early starts are counted: 1 + 3 + 9 + … + 3⁶ = 1,093
	/// scopes, one per path.
	private static let depth = 6

	/// `roots`, and `depth` layers of three types each, `L<layer>A` to `L<layer>C`, each instantiating the three types of
	/// the layer beneath it, so that each root's tree has a scope for each of `3^layer` paths to each layer. The types of
	/// layer `instantiatesLayer` and below are instantiated through an `Instantiator`.
	private static func ternaryTree(depth: Int, beneath roots: [String], rootDeclarations: [String], instantiatesLayer: Int? = nil) -> [String] {
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
			seamFixtureType(named: root, isRoot: true, isFinalClass: true, declarations: rootDeclarations + declarations(instantiatingLayer: 1))
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
