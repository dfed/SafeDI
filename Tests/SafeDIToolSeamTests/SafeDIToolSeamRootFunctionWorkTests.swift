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

/// How the search for a production root's root functions (`RootFunctionHoisting`) grows with the inline paths to one filled
/// seam call. The work is counted, not timed, so the check is the same on every machine and every run.
struct SafeDIToolSeamRootFunctionWorkTests: ~Copyable {
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
	mutating func generate_walksRootBodyOnceForItsRootFunctions_whenRootReachesFilledSeamCallAlongManyInlinePaths() async throws {
		// At three and five layers the last layer's screens are reached along 36 and 324 paths, each of which writes its own
		// call of `Home` (a call with fills is never shared between places). The seam's module walks its seam's body twice,
		// two levels each; each call's fill is walked once as it is built, ten levels; and the root's body is walked once,
		// its levels growing with the paths as its code does: 25 a path at three layers, 25.4 at five. The type key's
		// layout reads the root's walk, where it walked the body a second time before, which recorded the last count twice.
		var counts = [[Int]]()
		for layerCount in [3, 5] {
			try await counts.append(rootFunctionWork(layerCount: layerCount))
		}
		var expected = [[Int]]()
		for (pathCount, rootLevels) in [(36, 900), (324, 8_244)] {
			var walks = [2, 2]
			walks.append(contentsOf: Array(repeating: 10, count: pathCount))
			walks.append(rootLevels)
			expected.append(walks)
		}
		#expect(counts == expected)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The levels each walk for root functions reads while the app module's root is generated, in the order the walks run.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func rootFunctionWork(layerCount: Int) async throws -> [Int] {
		let (stream, continuation) = AsyncStream.makeStream(of: GenerationWork.self)
		_ = try await GenerationWork.$observer.withValue(TaskLocalFunction { continuation.yield($0) }) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Seam", packageName: "pkg", swiftFileContentByFilePath: ["Types.swift": Self.seam]),
					ModuleFixture(name: "App", packageName: "pkg", swiftFileContentByFilePath: ["Root.swift": Self.app(layerCount: layerCount)], dependencies: ["Seam"]),
				],
				integration: .moduleInfo,
				// The code is what the seam's other tests compare; this one counts how its root functions are found.
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
		continuation.finish()
		var counts = [Int]()
		for await work in stream where work.step == .findingRootFunctions {
			counts.append(work.elementCount)
		}
		return counts
	}

	/// `Home`, a seam whose `Api` its caller fills, which the seam's tree builds at one place.
	private static let seam = """
	import SafeDI

	nonisolated public protocol Api {}

	@Instantiable(generateDependencyTree: true)
	public final class Home: Instantiable {
	    public init(api: any Api) { self.api = api }
	    @Instantiated let api: any Api
	}
	"""

	/// `layerCount` layers of four screens beneath a root that opens the first layer: each screen opens the three screens of the
	/// next layer but the one at its own position through an `Instantiator`, so the last layer's screens are reached along
	/// `4 * 3^(layerCount - 1)` paths, and each of them calls `Home`, whose `Api` `Impl` fills.
	private static func app(layerCount: Int) -> String {
		var types = [
			"""
			import Seam
			import SafeDI

			@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
			public final class Impl: Api, Instantiable {
			    public init() {}
			}
			""",
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: (0..<4).map { "@Instantiated let screen\($0)Builder: Instantiator<Screen\($0)>" }),
		]
		for screen in 0..<(layerCount * 4) {
			let layer = screen / 4
			let opened = layer < layerCount - 1 ? (0..<4).filter { $0 != screen % 4 }.map { (layer + 1) * 4 + $0 } : []
			types.append(seamFixtureType(
				named: "Screen\(screen)",
				isFinalClass: true,
				declarations: opened.isEmpty ? ["@Instantiated let home: Home"] : opened.map { "@Instantiated let screen\($0)Builder: Instantiator<Screen\($0)>" },
			))
		}
		return types.joined(separator: "\n\n")
	}
}
