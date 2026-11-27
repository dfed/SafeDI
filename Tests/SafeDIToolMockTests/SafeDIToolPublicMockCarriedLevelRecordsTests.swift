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

/// The level functions node records make of a public mock's call of another module's public mock whose fills hold a place
/// of the caller's own: the caller's tree is built with its builders, whose holes the fills read the levels of, so a root
/// level function takes the struct of the caller's level, as the tree's does (`FillInnerScopes.ofPublicMockCall`).
struct SafeDIToolPublicMockCarriedLevelRecordsTests: ~Copyable {
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
	mutating func generate_makesLevelFunctionsTakingCallersLevelFromRecords_whenPublicMocksFillHoldsPlaceItCannotFill() async throws {
		// `Outer`'s public mock calls `Inner`'s and fills `Inner`'s hole `service` with `DefaultService`, whose `gadget` only
		// `App` can build: a place of `Outer`'s own inside the fill, whose struct `Outer`'s root level function takes.
		let modules = [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Service {}\npublic protocol Gadget {}",
				seamFixtureType(named: "Screen", declarations: ["@Forwarded public let id: Int", "@Instantiated public let service: any Service"]),
				Self.publicMockType(named: "Inner", declarations: ["@Instantiated public let screenBuilder: Instantiator<Screen>", "@Instantiated public let service: any Service"]),
			]),
			ModuleFixture(name: "Middle", packageName: "Mid", swiftFileContent: [
				seamFixtureType(named: "Tag", isFinalClass: true, declarations: []),
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"]),
				Self.publicMockType(named: "Outer", declarations: ["@Instantiated public let tag: Tag", "@Instantiated public let inner: Inner"]),
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
		let (stream, continuation) = AsyncStream.makeStream(of: LevelFunctionRecordsObservation.self)
		_ = try await LevelFunctionRecordsObservation.$observer.withValue({ continuation.yield($0) }) {
			try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		continuation.finish()
		var treeProjections = Set<String>()
		var recordsProjections = [String]()
		for await observation in stream {
			if observation.root == "Outer" {
				recordsProjections.append(observation.projection)
			} else if observation.root == nil {
				treeProjections.insert(observation.projection)
			}
		}

		// The tree with `Outer`'s builders hands its root level function the struct of `Outer`'s level, and node records do too.
		let carryingTreeProjections = treeProjections.filter { $0.contains("carriedInnerScopes: [SafeDICore.LevelFunctionRecord.Parameter(") }
		#expect(carryingTreeProjections.count == 1, "\(treeProjections)")
		#expect(recordsProjections.filter { carryingTreeProjections.contains($0) }.count == 1)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_makesLevelFunctionsFillingInPlaceFromRecords_whenPublicMocksCallPassesUpBuilderItDoesNotFill() async throws {
		// `Screen`'s public mock calls `Detail`'s, fills its place of `Store` and passes its place of `Api` up as a builder of
		// its own: a public mock's body holds only the struct its caller built, so the call hands no override closure a
		// function over the fill of `store`, which its level function then holds in place, as the tree's does.
		let modules = [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Store {}\npublic protocol Api {}",
				Self.publicMockType(named: "Detail", declarations: ["@Instantiated public let store: any Store", "@Instantiated public let api: any Api"]),
			]),
			ModuleFixture(name: "Other", packageName: "Mid", swiftFileContent: [
				Self.fulfillingType(named: "LiveStore", fulfilling: "Store", declarations: []),
				Self.publicMockType(named: "Screen", declarations: ["@Instantiated public let detail: Detail"]),
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
		let (stream, continuation) = AsyncStream.makeStream(of: LevelFunctionRecordsObservation.self)
		_ = try await LevelFunctionRecordsObservation.$observer.withValue({ continuation.yield($0) }) {
			try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		continuation.finish()
		var treeProjections = Set<String>()
		var recordsProjections = [String]()
		for await observation in stream {
			if observation.root == "Screen" {
				recordsProjections.append(observation.projection)
			} else if observation.root == nil {
				treeProjections.insert(observation.projection)
			}
		}

		#expect(recordsProjections.count == 1)
		#expect(recordsProjections.allSatisfy { treeProjections.contains($0) && $0.contains("form: SafeDICore.LevelMember.FillForm.inlined(") }, "\(recordsProjections)")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// A public struct named `name` that generates a public mock, whose initializer is `package`: no module of another
	/// package can build it inline, so each calls its mock.
	private static func publicMockType(named name: String, declarations: [String]) -> String {
		seamFixtureType(named: name, declarations: declarations)
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: .public)\n")
			.replacingOccurrences(of: "    public init(", with: "    package init(")
	}

	private static func fulfillingType(named name: String, fulfilling fulfilledType: String, declarations: [String]) -> String {
		seamFixtureType(named: name, declarations: declarations, conformances: ", \(fulfilledType)")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [\(fulfilledType).self])\n")
	}
}
