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

/// The fold that names the cases of a seam's place graph drafted from its facts world (`SeamPlacesDrafts.namingRoutes`)
/// does work in proportion to the seam's calls and the steps of the routes that name its cases: `Hub`, a seam in
/// `Feature`, builds a chain of types whose last holds `api: any Api`, which only `App` fulfills, or a lattice of types
/// each holding one, built both to its right and beneath.
struct SafeDIToolSeamPlaceNamingGrowthTests: ~Copyable {
	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	@Test(arguments: [8, 16, 32])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func namingRoutes_workInProportionToCallsAndRouteSteps_whenSeamsTreeIsChainWhoseLastTypeHoldsPlace(length: Int) async throws {
		var feature = ["public protocol Api {}"]
		for index in 0..<length {
			let next = index + 1 < length ? "@Instantiated public let next: C\(index + 1)" : "@Instantiated public let api: any Api"
			feature.append(seamFixtureType(named: "C\(index)", declarations: [next]))
		}
		feature.append(seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let first: C0"]))
		let naming = try await namingOfHub(feature: feature)
		#expect(naming.cases == 1)
		#expect(naming.work <= 4 * (naming.calls + naming.routeSteps), "\(naming.work) work for \(naming.calls) calls and \(naming.routeSteps) route steps")
	}

	@Test(arguments: [3, 4, 5])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func namingRoutes_workInProportionToCallsAndRouteSteps_whenSeamsTreeIsLatticeOfTypesThatEachHoldPlace(side: Int) async throws {
		var feature = ["public protocol Api {}"]
		for row in 0..<side {
			for column in 0..<side {
				var declarations = ["@Instantiated public let api: any Api"]
				if column + 1 < side {
					declarations.append("@Instantiated public let right: L\(row)x\(column + 1)")
				}
				if row + 1 < side {
					declarations.append("@Instantiated public let down: L\(row + 1)x\(column)")
				}
				feature.append(seamFixtureType(named: "L\(row)x\(column)", declarations: declarations))
			}
		}
		feature.append(seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let corner: L0x0"]))
		let naming = try await namingOfHub(feature: feature)
		#expect(naming.cases >= side * side)
		#expect(naming.work <= 4 * (naming.calls + naming.routeSteps), "\(naming.work) work for \(naming.calls) calls and \(naming.routeSteps) route steps")
	}

	/// The naming fold's line of `Hub`'s drafts report (`SeamPlacesDrafts.levelAndSiteDifferences(from:)`).
	private mutating func namingOfHub(feature: [String]) async throws -> (work: Int, cases: Int, routeSteps: Int, calls: Int) {
		let liveApi = seamFixtureType(named: "LiveApi", declarations: [], conformances: ", Api")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Api.self])\n")
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let hub: Hub"])
		let (stream, continuation) = AsyncStream.makeStream(of: String.self)
		// The lattice's routes grow exponentially with its side, so the per-site walk is not compared (`SeamPlaceTreeRoutes`).
		_ = try await SeamPlaceTreeRoutes.$areCompared.withValue(false) { try await NodeRecordsObservation.$observer.withValue({ report in
			guard report.root == "Hub" else { return }
			for line in report.placesDraftDifferences ?? [] where line.hasPrefix("report: naming: ") {
				continuation.yield(line)
			}
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
					ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [liveApi, root].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
				],
				integration: .moduleInfo,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		} }
		continuation.finish()
		var lines = [String]()
		for await line in stream {
			lines.append(line)
		}
		// "report: naming: W work, C cases, S route steps, V variants, N calls"
		let numbers = try #require(lines.first).split(separator: " ").compactMap { Int($0) }
		try #require(numbers.count == 5)
		return (numbers[0], numbers[1], numbers[2], numbers[4])
	}

	private var filesToDelete: [URL]
}
