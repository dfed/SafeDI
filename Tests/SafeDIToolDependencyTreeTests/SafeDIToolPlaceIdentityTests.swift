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

/// A place is a position in a root's tree that the body's ordered walk reaches, identified by the index at which the walk
/// first reaches it, never by the scope or generator that builds it (`PlaceObservation`).
struct SafeDIToolPlaceIdentityTests: ~Copyable {
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
	mutating func generate_numbersEachPlaceOfOneTypeApart_whenCousinsAndFillBuildIt() async throws {
		// `T` is built in three places: beneath `A` and beneath `B`, cousins whose scopes are built in one context, and inside
		// `App`'s fill of the seam `S`'s hole, which is hosted as the seam emitter's text. Each is a place of its own.
		let modules = [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Api {}",
				seamFixtureType(named: "Leaf", declarations: []),
				seamFixtureType(named: "T", declarations: ["@Instantiated let leaf: Leaf"]),
				seamFixtureType(named: "A", declarations: ["@Instantiated let t: T"]),
				seamFixtureType(named: "B", declarations: ["@Instantiated let t: T"]),
				seamFixtureType(named: "S", isSeam: true, declarations: ["@Instantiated let api: any Api"]),
			]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				seamFixtureType(named: "DefaultApi", isFinalClass: true, declarations: ["@Instantiated let t: T"], conformances: ", Api")
					.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Api.self])\n"),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let a: A", "@Instantiated let b: B", "@Instantiated let s: S"]),
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
		let (_, observations) = try await collectingPlaceObservations {
			try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
		#expect(observations.map(\.places).filter { !$0.isEmpty } == [[
			PlaceObservation.Place(index: 0, kind: .builtByFunction, functionNames: ["__safeDI_a"]),
			PlaceObservation.Place(index: 1, kind: .builtByFunction, functionNames: ["__safeDI_t"]),
			PlaceObservation.Place(index: 2, kind: .constantBuiltInPlace, functionNames: []),
			PlaceObservation.Place(index: 3, kind: .builtByFunction, functionNames: ["__safeDI_b"]),
			PlaceObservation.Place(index: 4, kind: .builtByFunction, functionNames: ["__safeDI_t"]),
			PlaceObservation.Place(index: 5, kind: .constantBuiltInPlace, functionNames: []),
			PlaceObservation.Place(index: 6, kind: .builtByFunction, functionNames: ["__safeDI_s"]),
			PlaceObservation.Place(index: 7, kind: .hostedSeamCode, functionNames: []),
		]])
		#expect(observations.flatMap(\.violations) == [])
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
