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

/// The case through which a seam passes up an inner seam's places holds the inner seam's enum and nothing else.
///
/// An adopter's report (item 2 of their reply to the nested scope enums): when that case also carried what the calling
/// type binds before the call, the seam built the payload at the call, inside the function that builds the inner seam,
/// where the inner seam's own forwarded properties are parameters under the same labels. So the payload read the inner
/// seam's value where the calling type's has the same label (a compile error when the types differ, a wrong value when
/// they match), and the closure that hands the inner enum up captured every value the payload held, which inline never
/// retains.
struct SafeDIToolSeamPassedUpValuesTests: ~Copyable {
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
	mutating func generate_compiles_whenInnerSeamForwardsLabelOuterSeamForwardsAsAnotherType() async throws {
		// `Detail` forwards `id: Int`, `List` forwards `id: String`: the payload of `List`'s case for `detailBuilder` is built
		// inside the function that builds `Detail`, whose `id: Int` hides `List`'s.
		_ = try await executeSafeDIToolMultiModuleTest(
			modules: Self.innerAndOuterModules(
				inner: [Self.detail(forwarding: "id: Int")],
				outer: [seamFixtureType(named: "List", isSeam: true, declarations: ["@Forwarded public let id: String", "@Instantiated public let detailBuilder: Instantiator<Detail>"])],
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compiles_whenInnerSeamForwardsLabelOuterSeamForwardsAsAnotherTypeInOneModule() async throws {
		_ = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "Feature",
					packageName: "Shop",
					swiftFileContent: [
						"public protocol Api {}",
						Self.detail(forwarding: "id: Int"),
						seamFixtureType(named: "List", isSeam: true, declarations: ["@Forwarded public let id: String", "@Instantiated public let detailBuilder: Instantiator<Detail>"]),
					],
					swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration,
				),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compiles_whenTypeInsideOuterSeamForwardsLabelInnerSeamForwardsAsAnotherType() async throws {
		// `List` is no seam but a type `Home`'s tree builds: its level is bound inside the function that builds `Detail` too.
		_ = try await executeSafeDIToolMultiModuleTest(
			modules: Self.innerAndOuterModules(
				inner: [Self.detail(forwarding: "id: Int")],
				outer: [
					seamFixtureType(named: "List", declarations: ["@Forwarded public let id: String", "@Instantiated public let detailBuilder: Instantiator<Detail>"]),
					seamFixtureType(named: "Home", isSeam: true, declarations: ["@Instantiated public let listBuilder: Instantiator<List>"]),
				],
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compiles_whenInnerSeamForwardsOptionalOfLabelOuterSeamForwardsByValue() async throws {
		// The payload's `user: User` is built from `Detail`'s `user: User?`.
		_ = try await executeSafeDIToolMultiModuleTest(
			modules: Self.innerAndOuterModules(
				inner: [seamFixtureType(named: "User", isFinalClass: true, declarations: []), Self.detail(forwarding: "user: User?")],
				outer: [seamFixtureType(named: "List", isSeam: true, declarations: ["@Forwarded public let user: User", "@Instantiated public let detailBuilder: Instantiator<Detail>"])],
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compiles_whenOuterSeamDefersPassThroughOfLabelInnerSeamForwards() async throws {
		// `Reader` receives `user`, so `List` takes it as a deferred parameter and its payload holds the memo, a
		// `LazilyInstantiated<User>`, which is built from `Detail`'s `user: User`.
		_ = try await executeSafeDIToolMultiModuleTest(
			modules: Self.innerAndOuterModules(
				inner: [seamFixtureType(named: "User", isFinalClass: true, declarations: []), Self.detail(forwarding: "user: User")],
				outer: [
					seamFixtureType(named: "Reader", declarations: ["@Received public let user: User"]),
					seamFixtureType(named: "List", isSeam: true, declarations: ["@Instantiated public let reader: Reader", "@Instantiated public let detailBuilder: Instantiator<Detail>"]),
				],
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func plainInitializer_handsBuilderEachSeamsOwnValue_whenInnerSeamForwardsLabelOfOuterSeamsValue() async throws {
		// Both forward `id: Int`. A hand-written builder reads `List`'s `id` at `List`'s own place, `List(id: 1)`'s, and
		// `Detail`'s at the place `List` passes up, the `2` its instantiator forwards, through the case that holds `Detail`'s
		// enum alone.
		let modules = Self.innerAndOuterModules(
			inner: [Self.detail(forwarding: "id: Int")],
			outer: [
				seamFixtureType(named: "List", isSeam: true, declarations: ["@Forwarded public let id: Int", "@Instantiated public let api: any Api", "@Instantiated public let detailBuilder: Instantiator<Detail>"]),
				Self.recorder,
				"""
				struct Live: Api {}

				func identifiersTheBuilderReads() -> [Int] {
				    let recorder = Recorder()
				    let list = List(id: 1, apiBuilder: { scope in
				        switch scope {
				        case let .api(list):
				            recorder.values.append(list.id)
				        case let .detailBuilder(.api(detail)):
				            recorder.values.append(detail.id)
				        }
				        return Live()
				    })
				    _ = list.detailBuilder.instantiate(2)
				    return recorder.values
				}
				""",
			],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let description = try await DifferentialValueOracle.describe(
			DifferentialValuePath(output: output, modules: modules),
			probes: [DifferentialValueProbe("identifiersTheBuilderReads()")],
			filesToDelete: &filesToDelete,
		)
		if compileVerificationIsEnabled {
			#expect(description == """
			probe identifiersTheBuilderReads()
			Array<Int>
			  0: Int 1
			  1: Int 2

			""")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func plainInitializer_handsBuilderEachNodesOwnValue_whenSeamBuildsItselfAgainThroughInstantiator() async throws {
		// `Node` forwards `id` and builds another `Node` through `nextBuilder`: the place under the second node is handed its
		// own `id` in the case for `api`, which the case for `nextBuilder` holds alone.
		let modules = [
			ModuleFixture(
				name: "Feature",
				packageName: "Shop",
				swiftFileContent: [
					"public protocol Api {}",
					seamFixtureType(named: "Node", isSeam: true, isFinalClass: true, declarations: ["@Forwarded public let id: Int", "@Instantiated public let api: any Api", "@Instantiated public let nextBuilder: Instantiator<Node>"]),
					Self.recorder,
					"""
					struct Live: Api {}

					func identifiersTheBuilderReads() -> [Int] {
					    let recorder = Recorder()
					    let node = Node(id: 1, apiBuilder: { scope in
					        switch scope {
					        case let .api(values):
					            recorder.values.append(values.id)
					        case let .nextBuilder(.api(inner)):
					            recorder.values.append(inner.id)
					        default:
					            break
					        }
					        return Live()
					    })
					    _ = node.nextBuilder.instantiate(2)
					    return recorder.values
					}
					""",
				],
				swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration,
			),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let description = try await DifferentialValueOracle.describe(
			DifferentialValuePath(output: output, modules: modules),
			probes: [DifferentialValueProbe("identifiersTheBuilderReads()")],
			filesToDelete: &filesToDelete,
		)
		if compileVerificationIsEnabled {
			#expect(description == """
			probe identifiersTheBuilderReads()
			Array<Int>
			  0: Int 1
			  1: Int 2

			""")
		}
	}

	@Test(arguments: [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_releasesOuterSeamsValues_whenValueOuterSeamBuiltBeforeInnerSeamHoldsInnerSeam(fillsWithGeneratedCode: Bool) async throws {
		// `Home` builds `navigator`, then `detailBuilder`, which builds `Detail`, a seam of another module whose place `api`
		// `Home` passes up. Inline, nothing `Detail` holds captures `navigator`, so a navigator that holds a detail is freed
		// with `Home`. The closure that hands `Detail`'s enum up is the builder `Detail` holds, so the case it builds carries
		// no value of `Home`'s.
		let modules = Self.innerAndOuterModules(
			inner: [
				seamFixtureType(named: "Leaf", isFinalClass: true, declarations: ["@Instantiated public let api: any Api"]),
				seamFixtureType(named: "Detail", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let leafBuilder: Instantiator<Leaf>"]),
			],
			outer: [
				"""
				@Instantiable
				public final class Navigator: Instantiable {
				    public init() {}

				    public var stack = [AnyObject]()
				}
				""",
				seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let navigator: Navigator", "@Instantiated public let detailBuilder: Instantiator<Detail>"]),
			],
			app: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "Live", fulfilling: "Api", declarations: []),
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let home: Home"]),
				"""
				func homeIsFreedWithItsNavigator() -> Bool {
				    weak var weakNavigator: Navigator?
				    do {
				        let home = \(fillsWithGeneratedCode ? "Root().home" : "Home(apiBuilder: { _ in Live() })")
				        weakNavigator = home.navigator
				        home.navigator.stack.append(home.detailBuilder.instantiate())
				    }
				    return weakNavigator == nil
				}
				""",
			],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let description = try await DifferentialValueOracle.describe(
			DifferentialValuePath(output: output, modules: modules),
			probes: [DifferentialValueProbe("homeIsFreedWithItsNavigator()")],
			filesToDelete: &filesToDelete,
		)
		if compileVerificationIsEnabled {
			#expect(description == """
			probe homeIsFreedWithItsNavigator()
			Bool true

			""")
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Detail`, a seam that forwards `forwarded` and holds a place of `Api`.
	private static func detail(forwarding forwarded: String) -> String {
		seamFixtureType(named: "Detail", isSeam: true, isFinalClass: true, declarations: ["@Forwarded public let \(forwarded)", "@Instantiated public let api: any Api"])
	}

	/// A box a hand-written builder records what it reads in.
	private static let recorder = """
	final class Recorder {
	    var values = [Int]()
	}
	"""

	/// `Inner`, in package `Shop`, which declares `Api` and `inner`'s types; `Outer`, in package `Other`, which declares
	/// `outer`'s; and, when `app` is not empty, `App`, which declares `app`'s. Every module sets
	/// `generatePlainDependencyTreeInitializers`.
	private static func innerAndOuterModules(inner: [String], outer: [String], app: [String] = []) -> [ModuleFixture] {
		var modules = [
			ModuleFixture(name: "Inner", packageName: "Shop", swiftFileContent: ["public protocol Api {}"] + inner, swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration),
			ModuleFixture(name: "Outer", packageName: "Other", swiftFileContent: outer.map { "import Inner\n\n" + $0 }, swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration, dependencies: ["Inner"]),
		]
		if !app.isEmpty {
			modules.append(ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Inner\nimport Outer\n\n" + $0 }, dependencies: ["Inner", "Outer"]))
		}
		return modules
	}
}
