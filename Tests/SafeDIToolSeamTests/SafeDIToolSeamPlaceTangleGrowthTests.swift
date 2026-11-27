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

/// A seam's tree that is a tangle of cycles no type always encloses: `Hub`, a seam in `Feature`, holds an `Instantiator`
/// of each member, and each member holds one of every other member, a `Mark` of its own and `api: any Api`, which only
/// `App` fulfills. Which member a builder call closes on depends on the set of members on the path above it (on
/// `Hub → M0 → M2`, `M2`'s `m1Builder` opens a fresh `M1`; on `Hub → M0 → M1 → M2`, it closes on the `M1` above), so a
/// stored fact that follows where a call closes grows with the paths, which grow faster than exponentially with the
/// members. Where a call closes is a fact of the route, which the place graph's query answers.
struct SafeDIToolSeamPlaceTangleGrowthTests: ~Copyable {
	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	@Test(arguments: [3, 4])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func placesGraph_storesAtMostOneLevelPerDeclarationAndEdge_whenSeamsTreeIsTangleOfMembersThatEachBuildEveryOther(memberCount: Int) async throws {
		let places = try await placesOfHub(memberCount: memberCount)
		// `Hub` and each member's build of itself, its mark and its `api`, and an edge from `Hub` to each member and from
		// each member to its mark, its `api` and every other member.
		let declarationCount = 1 + 3 * memberCount
		let edgeCount = memberCount + memberCount * (memberCount + 1)
		#expect(places.levels.count <= declarationCount + edgeCount, "\(places.levels.count) levels for \(memberCount) members")
	}

	private mutating func placesOfHub(memberCount: Int) async throws -> SeamSignature.Places {
		let members = (0..<memberCount).map { "M\($0)" }
		var feature = ["public protocol Api {}"]
		for member in members {
			feature.append(seamFixtureType(named: "Mark\(member)", declarations: []))
			let builders = members.filter { $0 != member }.map { "@Instantiated public let \($0.lowercased())Builder: Instantiator<\($0)>" }
			feature.append(seamFixtureType(named: member, declarations: ["@Instantiated public let mark\(member): Mark\(member)"] + builders + ["@Instantiated public let api: any Api"]))
		}
		feature.append(seamFixtureType(named: "Hub", isSeam: true, declarations: members.map { "@Instantiated public let \($0.lowercased())Builder: Instantiator<\($0)>" }))
		let liveApi = seamFixtureType(named: "LiveApi", declarations: [], conformances: ", Api")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Api.self])\n")
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let hub: Hub"])
		let (stream, continuation) = AsyncStream.makeStream(of: SeamSignature.Places.self)
		_ = try await SeamPlaceLevels.$observer.withValue({ placeLevels in
			if let observation = placeLevels.placesObservation, observation.seamType.asSource == "Hub" {
				continuation.yield(observation.places)
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
		}
		continuation.finish()
		var observed = [SeamSignature.Places]()
		for await places in stream {
			observed.append(places)
		}
		return try #require(observed.first)
	}

	private var filesToDelete: [URL]
}
