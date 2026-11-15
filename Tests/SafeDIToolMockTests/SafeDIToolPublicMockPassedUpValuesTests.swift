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

/// The case through which a public mock passes up the places of another module's public mock it calls holds that mock's
/// enum and nothing else. When it also carried what the calling type binds before the call, the mock built that payload at
/// the call, inside the function that builds the called mock's type, where that type's forwarded properties are parameters
/// under their labels, so the payload read the called type's value where the calling type's has the same label: a compile
/// error when the types differ, a wrong value when they match (an adopter's report, item 2).
struct SafeDIToolPublicMockPassedUpValuesTests: ~Copyable {
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
	mutating func generate_compiles_whenCalledPublicMockForwardsLabelCallingMockInstantiatesAsAnotherType() async throws {
		// `List` instantiates `id: Tag` before `detailBuilder`; `Detail`'s mock, which `List`'s calls, forwards `id: Int`.
		_ = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(
				outer: [
					seamFixtureType(named: "Tag", isFinalClass: true, declarations: []),
					Self.publicMockType(named: "List", declarations: ["@Instantiated public let id: Tag", "@Instantiated public let detailBuilder: Instantiator<Detail>"]),
				],
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compiles_whenTypeInsidePublicMockForwardsLabelCalledPublicMockForwardsAsAnotherType() async throws {
		_ = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(
				outer: [
					seamFixtureType(named: "List", isFinalClass: true, declarations: ["@Forwarded public let id: String", "@Instantiated public let detailBuilder: Instantiator<Detail>"]),
					Self.publicMockType(named: "Home", declarations: ["@Instantiated public let listBuilder: Instantiator<List>"]),
				],
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_handsBuilderCallingTypesValueAtItsOwnPlace_whenCalledPublicMockForwardsLabelOfCallingTypesValue() async throws {
		// `List` and `Detail` both forward `id: Int`. A hand-written builder reads `List`'s `id` at `List`'s own place, `1`,
		// never the `2` `List`'s instantiator forwards to `Detail`, and reaches `Detail`'s place through the case that holds
		// `Detail`'s mock's enum alone.
		let modules = Self.modules(
			outer: [
				seamFixtureType(named: "List", isFinalClass: true, declarations: ["@Forwarded public let id: Int", "@Instantiated public let api: any Api", "@Instantiated public let detailBuilder: Instantiator<Detail>"]),
				Self.publicMockType(named: "Home", declarations: ["@Instantiated public let listBuilder: Instantiator<List>"]),
				"""
				struct Live: Api {}

				final class Recorder {
				    var values = [String]()
				}

				func placesTheBuilderFills() -> [String] {
				    let recorder = Recorder()
				    let home = Home.mock(apiBuilder: { scope in
				        switch scope {
				        case let .listBuilder(_, .api(list)):
				            recorder.values.append("list \\(list.id)")
				        case .listBuilder(_, .detailBuilder(.api)):
				            recorder.values.append("detail")
				        }
				        return Live()
				    })
				    _ = home.listBuilder.instantiate(1).detailBuilder.instantiate(2)
				    return recorder.values
				}
				""",
			],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let description = try await DifferentialValueOracle.describe(
			DifferentialValuePath(output: output, modules: modules),
			probes: [DifferentialValueProbe("placesTheBuilderFills()")],
			filesToDelete: &filesToDelete,
		)
		if compileVerificationIsEnabled {
			#expect(description == """
			probe placesTheBuilderFills()
			Array<String>
			  0: String "list 1"
			  1: String "detail"

			""")
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `name`, a final class with `declarations` whose public mock is generated and whose initializer is `internal`, so a
	/// mock in another module calls its public mock rather than building it.
	private static func publicMockType(named name: String, declarations: [String]) -> String {
		seamFixtureType(named: name, isFinalClass: true, declarations: declarations)
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: .public)\n")
			.replacingOccurrences(of: "    public init(", with: "    init(")
	}

	/// `Inner`, in package `Shop`, which declares `Api` and `Detail`, whose public mock forwards `id: Int` and holds a place
	/// of `Api`; and `Outer`, in package `Other`, which declares `outer`'s types.
	private static func modules(outer: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Inner", packageName: "Shop", swiftFileContent: [
				"public protocol Api {}",
				publicMockType(named: "Detail", declarations: ["@Forwarded public let id: Int", "@Instantiated public let api: any Api"]),
			]),
			ModuleFixture(name: "Outer", packageName: "Other", swiftFileContent: outer.map { "import Inner\n\n" + $0 }, dependencies: ["Inner"]),
		]
	}
}
