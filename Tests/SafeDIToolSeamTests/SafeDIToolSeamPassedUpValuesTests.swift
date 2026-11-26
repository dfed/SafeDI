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
	mutating func plainInitializer_buildsEachPlaceFromBuilder_whenInnerSeamForwardsLabelOfOuterSeamsValue() async throws {
		// Both forward `id: Int`. `List`'s generated-only initializer calls the member for the place it passes up inside the
		// function that builds `Detail`, whose `id` hides `List`'s, so that member's values carry none of `List`'s. A
		// hand-written builder takes no value: it builds `List`'s own place and the place `List` passes up, once each, and each
		// seam keeps its own `id`.
		let modules = Self.innerAndOuterModules(
			inner: [Self.detail(forwarding: "id: Int")],
			outer: [
				seamFixtureType(named: "List", isSeam: true, declarations: ["@Forwarded public let id: Int", "@Instantiated public let api: any Api", "@Instantiated public let detailBuilder: Instantiator<Detail>"]),
				Self.countedApi,
				"""
				func identifiersAndBuildOrder() -> [Int] {
				    var count = 0
				    let list = List(id: 1, apiBuilder: {
				        count += 1
				        return Live(count: count)
				    })
				    let detail = list.detailBuilder.instantiate(2)
				    return [list.id, (list.api as? Live)?.count ?? 0, detail.id, (detail.api as? Live)?.count ?? 0]
				}
				""",
			],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Inner"]?.generatedFiles == ["Inner.swift": generatedFileHeader + """
		extension Detail {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let api: (Int) -> __safeDI_Built

		        public init(api: @escaping (Int) -> __safeDI_Built) {
		            self.api = api
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { _ in __safeDI_builder() })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(id: Int, apiBuilder: @escaping () -> any Api) {
		        self.init(__safeDI_id: id, __safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_id id: Int, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let api: any Api = __safeDI_apiBuilder.api(id)
		        self.init(id: id, api: api)
		    }
		}

		extension Detail {
		    public enum __safeDI_Detail_5BF800DF64AF87BC {}
		}
		"""])
		#expect(output.modules["Outer"]?.generatedFiles == ["Outer.swift": generatedFileHeader + """
		#if canImport(Inner)
		import Inner
		#endif

		extension List {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let api: (Int, Instantiator<Detail>) -> __safeDI_Built
		        public let detailBuilder: Detail.__safeDI_ApiCarrier<__safeDI_Built>

		        public init(api: @escaping (Int, Instantiator<Detail>) -> __safeDI_Built, detailBuilder: Detail.__safeDI_ApiCarrier<__safeDI_Built>) {
		            self.api = api
		            self.detailBuilder = detailBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { _, _ in __safeDI_builder() }, detailBuilder: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public init(id: Int, apiBuilder: @escaping () -> any Api) {
		        self.init(__safeDI_id: id, __safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public init(__safeDI_id id: Int, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        func __safeDI_detailBuilder(id: Int) -> Detail {
		            _ = Detail.__safeDI_Detail_5BF800DF64AF87BC.self // If this line does not compile, compile the code SafeDI generates for module Inner into Inner: under Bazel, add Inner’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Detail(__safeDI_id: id, __safeDI_apiBuilder: __safeDI_apiBuilder.detailBuilder)
		        }
		        let detailBuilder = Instantiator<Detail> {
		            __safeDI_detailBuilder(id: $0)
		        }
		        let api: any Api = __safeDI_apiBuilder.api(id, detailBuilder)
		        self.init(id: id, api: api, detailBuilder: detailBuilder)
		    }
		}

		extension List {
		    public enum __safeDI_List_BECBEBC190875F5C {}
		}
		"""])
		let description = try await DifferentialValueOracle.describe(
			DifferentialValuePath(output: output, modules: modules),
			probes: [DifferentialValueProbe("identifiersAndBuildOrder()")],
			filesToDelete: &filesToDelete,
		)
		if compileVerificationIsEnabled {
			#expect(description == """
			probe identifiersAndBuildOrder()
			Array<Int>
			  0: Int 1
			  1: Int 1
			  2: Int 2
			  3: Int 2

			""")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func plainInitializer_buildsEachPlaceFromBuilder_whenSeamBuildsItselfAgainThroughInstantiator() async throws {
		// `Node` forwards `id` and builds another `Node` through `nextBuilder`: the hand-written builder builds the place of
		// each node, the second's through the level `nextBuilder` reaches, once each, and each node keeps its own `id`.
		let modules = [
			ModuleFixture(
				name: "Feature",
				packageName: "Shop",
				swiftFileContent: [
					"public protocol Api {}",
					seamFixtureType(named: "Node", isSeam: true, isFinalClass: true, declarations: ["@Forwarded public let id: Int", "@Instantiated public let api: any Api", "@Instantiated public let nextBuilder: Instantiator<Node>"]),
					Self.countedApi,
					"""
					func identifiersAndBuildOrder() -> [Int] {
					    var count = 0
					    let node = Node(id: 1, apiBuilder: {
					        count += 1
					        return Live(count: count)
					    })
					    let next = node.nextBuilder.instantiate(2)
					    return [node.id, (node.api as? Live)?.count ?? 0, next.id, (next.api as? Live)?.count ?? 0]
					}
					""",
				],
				swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration,
			),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Node {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let api: (Int, Instantiator<Node>) -> __safeDI_Built
		        public let nextBuilder: () -> Node.__safeDI_ApiCarrier<__safeDI_Built>

		        public init(api: @escaping (Int, Instantiator<Node>) -> __safeDI_Built, nextBuilder: @escaping () -> Node.__safeDI_ApiCarrier<__safeDI_Built>) {
		            self.api = api
		            self.nextBuilder = nextBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { _, _ in __safeDI_builder() }, nextBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(id: Int, apiBuilder: @escaping () -> any Api) {
		        self.init(__safeDI_id: id, __safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_id id: Int, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        func __safeDI_nextBuilder(id: Int) -> Node {
		            _ = Node.__safeDI_Node_E5AA19DA80BC605E.self
		            return Node(__safeDI_id: id, __safeDI_apiBuilder: __safeDI_apiBuilder.nextBuilder())
		        }
		        let nextBuilder = Instantiator<Node> {
		            __safeDI_nextBuilder(id: $0)
		        }
		        let api: any Api = __safeDI_apiBuilder.api(id, nextBuilder)
		        self.init(id: id, api: api, nextBuilder: nextBuilder)
		    }
		}

		extension Node {
		    public enum __safeDI_Node_E5AA19DA80BC605E {}
		}
		"""])
		let description = try await DifferentialValueOracle.describe(
			DifferentialValuePath(output: output, modules: modules),
			probes: [DifferentialValueProbe("identifiersAndBuildOrder()")],
			filesToDelete: &filesToDelete,
		)
		if compileVerificationIsEnabled {
			#expect(description == """
			probe identifiersAndBuildOrder()
			Array<Int>
			  0: Int 1
			  1: Int 1
			  2: Int 2
			  3: Int 2

			""")
		}
	}

	@Test(arguments: [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_releasesOuterSeamsValues_whenValueOuterSeamBuiltBeforeInnerSeamHoldsInnerSeam(fillsWithGeneratedCode: Bool) async throws {
		// `Home` builds `navigator`, then `detailBuilder`, which builds `Detail`, a seam of another module whose place `api`
		// `Home` passes up. Inline, nothing `Detail` holds captures `navigator`, so a navigator that holds a detail is freed
		// with `Home`. The builder `Detail` holds is the one `Home` passes up, which takes nothing, so it carries no value of
		// `Home`'s.
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
				        let home = \(fillsWithGeneratedCode ? "Root().home" : "Home(apiBuilder: { Live() })")
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

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsEachRouteItsNearestValue_whenRootFillsPlaceTwoSeamsUpWhoseSecondRouteAloneReadsRootsValue() async throws {
		// `Home` holds a place of `Api` under `first` and under `second`, one case, and `Shell` passes it up to `Root`, whose
		// `LiveApi` receives `token`. Inline, the `LiveApi` under `first` reads `First`’s token, and the one under `second`,
		// where nothing between `Root` and the place declares one, reads `Root`’s.
		let modules = Self.innerAndOuterModules(
			inner: [
				seamFixtureType(named: "Token", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Panel", isFinalClass: true, declarations: ["@Instantiated public let api: any Api"]),
				seamFixtureType(named: "First", isFinalClass: true, declarations: ["@Instantiated public let token: Token", "@Instantiated public let panel: Panel"]),
				seamFixtureType(named: "Second", isFinalClass: true, declarations: ["@Instantiated public let panel: Panel"]),
				seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let first: First", "@Instantiated public let second: Second"]),
			],
			outer: [
				seamFixtureType(named: "Shell", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let home: Home"]),
			],
			app: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received public let token: Token"]),
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let token: Token", "@Instantiated public let shell: Shell"]),
				"""
				func eachApiReadsItsNearestToken() -> [Bool] {
				    let root = Root()
				    let home = root.shell.home
				    return [(home.first.panel.api as? LiveApi)?.token === home.first.token, (home.second.panel.api as? LiveApi)?.token === root.token]
				}
				""",
			],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let description = try await DifferentialValueOracle.describe(
			DifferentialValuePath(output: output, modules: modules),
			probes: [DifferentialValueProbe("eachApiReadsItsNearestToken()")],
			filesToDelete: &filesToDelete,
		)
		if compileVerificationIsEnabled {
			#expect(description == """
			probe eachApiReadsItsNearestToken()
			Array<Bool>
			  0: Bool true
			  1: Bool true

			""")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsDeclarationBoundAfterPlace_whenRootFillsPlaceTwoSeamsUpWhoseSecondRouteAloneLeavesLabelUncarried() async {
		// `Home` holds a place of `Api` under `first` and under `second`, one case, and `Shell` passes it up to `Root`. Only
		// `Second` declares `token`, which receives `panel` and so is built after it: inline, the `LiveApi` under `second`
		// would read it, and no builder is handed it, so the second route alone makes `Root`’s fill an error.
		let modules = Self.innerAndOuterModules(
			inner: [
				seamFixtureType(named: "Token", isFinalClass: true, declarations: ["@Received public let panel: Panel"]),
				seamFixtureType(named: "Panel", isFinalClass: true, declarations: ["@Instantiated public let api: any Api"]),
				seamFixtureType(named: "First", isFinalClass: true, declarations: ["@Instantiated public let panel: Panel"]),
				seamFixtureType(named: "Second", isFinalClass: true, declarations: ["@Instantiated public let panel: Panel", "@Instantiated public let token: Token"]),
				seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let first: First", "@Instantiated public let second: Second"]),
			],
			outer: [
				seamFixtureType(named: "Shell", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let home: Home"]),
			],
			app: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received(onlyIfAvailable: true) public let token: Token?"]),
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let shell: Shell"]),
			],
		)
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):10:5: error: `LiveApi` receives `token: Token?`, which `Second` builds only after `Home`’s tree calls the builder for `Panel`’s `api: any Api` (`api` of `apiBuilder_second_panel`), so SafeDI does not hand it to that builder. Declare an @Instantiable type that fulfills `Api` in module `Inner` or a module it lists among its SafeDI dependencies.
			\(fixtures["Inner"]!["Second.swift"]):9:5: note: `Second` declares `token: Token` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Detail`, a seam that forwards `forwarded` and holds a place of `Api`.
	private static func detail(forwarding forwarded: String) -> String {
		seamFixtureType(named: "Detail", isSeam: true, isFinalClass: true, declarations: ["@Forwarded public let \(forwarded)", "@Instantiated public let api: any Api"])
	}

	/// The `Api` a hand-written builder builds, numbered in the order the builder is called.
	private static let countedApi = """
	struct Live: Api {
	    let count: Int
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
