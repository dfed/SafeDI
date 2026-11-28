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

/// A module's seam signatures are settled one level of seam components at a time, the components of a level on as many
/// tasks as there are processors, each task in an ID space of its own; the results are merged in component order. So what
/// a module generates is the same however many tasks settle a level.
struct SafeDIToolSeamParallelSignatureTests: ~Copyable {
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
	mutating func generate_generatesTheSameCodeAndModuleInfoOnEveryTaskCount_whenLevelsHoldManyIndependentSeams() async throws {
		// Twenty-five seams in three levels: eighteen that reach no seam, six that each reach three of those, and one that
		// reaches the six. Three and four tasks split the first level into runs of six and of four or five, and the second
		// into runs of two or of one and two; the third level is one component, which the module's own task settles.
		let serial = try await generated(taskCount: 1, verifiesCompilation: true)
		for taskCount in [2, 3, 4] {
			let parallel = try await generated(taskCount: taskCount, verifiesCompilation: false)
			#expect(parallel.files == serial.files, "\(taskCount) tasks generate other code than one task")
			#expect(parallel.seamSignatures == serial.seamSignatures, "\(taskCount) tasks store other seam signatures than one task")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_settlesEachLevelOnSeveralTasks_whenItsSeamsReachTypesOfTheirOwn() async throws {
		// Each of the eighteen inner seams reaches its own leaf, and each of the six middle seams three inner seams of its
		// own: every type a level reaches is reached by one component.
		let levels = try await Self.observedLevels {
			try await generated(taskCount: 4, verifiesCompilation: false)
		}
		#expect(levels == [
			SeamSignatureLevel(componentCount: 18, taskCount: 4),
			SeamSignatureLevel(componentCount: 6, taskCount: 4),
			SeamSignatureLevel(componentCount: 1, taskCount: 1),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_settlesLevelOnOneTask_whenItsSeamsReachMostlyTheSameTypes() async throws {
		// Three layers of three seams, each seam opening every seam of the layer beneath it. The bottom layer's seams each
		// reach their own leaf (six distinct types of six); the middle layer's each reach the bottom layer and its leaves
		// (nine of twenty-one), and the top layer's both layers beneath (twelve of thirty), so only the bottom layer is
		// settled on several tasks.
		let leaves = (0..<3).map { seamFixtureType(named: "Leaf\($0)", declarations: []) }
		let bottom = (0..<3).map { seamFixtureType(named: "Bottom\($0)", isSeam: true, declarations: ["@Instantiated let leaf\($0): Leaf\($0)"]) }
		let middle = (0..<3).map { index in
			seamFixtureType(named: "Middle\(index)", isSeam: true, declarations: (0..<3).map { "@Instantiated let bottom\($0): Bottom\($0)" })
		}
		let top = (0..<3).map { index in
			seamFixtureType(named: "Top\(index)", isSeam: true, declarations: (0..<3).map { "@Instantiated let middle\($0): Middle\($0)" })
		}
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: (0..<3).map { "@Instantiated let top\($0): Top\($0)" })
		let levels = try await Self.observedLevels {
			try await SeamSignatureObservation.$width.withValue(4) {
				_ = try await executeSafeDIToolTest(
					swiftFileContent: [root] + top + middle + bottom + leaves,
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
					moduleMembershipArguments: ["--module-name", "App"],
				)
			}
		}
		#expect(levels == [
			SeamSignatureLevel(componentCount: 3, taskCount: 3),
			SeamSignatureLevel(componentCount: 3, taskCount: 1),
			SeamSignatureLevel(componentCount: 3, taskCount: 1),
		])
	}

	// MARK: Private

	/// The levels of seam components the module's own signature computation settles while `body` runs, in level order.
	private static func observedLevels(_ body: () async throws -> some Any) async throws -> [SeamSignatureLevel] {
		let (stream, continuation) = AsyncStream.makeStream(of: SeamSignatureLevel.self)
		_ = try await SeamSignatureObservation.$observesLevels.withValue(TaskLocalFunction { continuation.yield($0) }) {
			try await body()
		}
		continuation.finish()
		var levels = [SeamSignatureLevel]()
		for await level in stream {
			levels.append(level)
		}
		return levels
	}

	private var filesToDelete: [URL]

	/// What a module generates: its files' code, and the seam signatures its module info file stores, as JSON whose
	/// fixture directory, which each run names anew, is spelled `FIXTURES`.
	private struct Generated {
		let files: [String: String]
		let seamSignatures: String
	}

	/// What the module of twenty-five seams generates when `taskCount` tasks settle each level of its seam components.
	private mutating func generated(taskCount: Int, verifiesCompilation: Bool) async throws -> Generated {
		let token = """
		@Instantiable
		public struct Token: Instantiable {
		    public init() {}
		}
		"""
		let innerSeams = (0..<18).flatMap { index in
			[
				seamFixtureType(named: "Leaf\(index)", declarations: ["@Received let token: Token"]),
				seamFixtureType(named: "Inner\(index)", isSeam: true, declarations: ["@Instantiated let leaf\(index): Leaf\(index)"]),
			]
		}
		let middleSeams = (0..<6).map { index in
			seamFixtureType(named: "Middle\(index)", isSeam: true, declarations: (0..<3).map { "@Instantiated let inner\(3 * index + $0): Inner\(3 * index + $0)" })
		}
		let outerSeam = seamFixtureType(named: "Outer", isSeam: true, declarations: (0..<6).map { "@Instantiated let middle\($0): Middle\($0)" })
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let token: Token", "@Instantiated let outer: Outer"])
		let output = try await SeamSignatureObservation.$width.withValue(taskCount) {
			try await executeSafeDIToolTest(
				swiftFileContent: [token, root, outerSeam] + middleSeams + innerSeams,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				skipCompileVerification: !verifiesCompilation,
				moduleMembershipArguments: ["--module-name", "App"],
			)
		}
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys]
		let seamSignatures = try #require(output.moduleInfoFile?.seamSignatures).decoded
		#expect(seamSignatures.count == 25)
		let fixtureDirectory = URL(fileURLWithPath: output.fixtures["Token.swift"]).deletingLastPathComponent().path
		return try Generated(
			files: #require(output.generatedFiles),
			seamSignatures: String(decoding: encoder.encode(seamSignatures), as: UTF8.self)
				.replacingOccurrences(of: fixtureDirectory, with: "FIXTURES"),
		)
	}
}
