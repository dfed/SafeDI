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

/// A hole on a cycle in a seam's tree. `Hub`, a seam in `Feature`, builds `A`, which builds `B`, whose `aBuilder`
/// re-enters the function `Hub`'s tree builds `A` with. `A` instantiates `api: any Api`, which `Feature` cannot build (a
/// hole), and `App` fills it with `LiveApi`. Inline, the `A` that `B` builds again receives `B`'s declarations through the
/// function's parameters; a fill reads the scope struct or the caller's scope, which hold the same values at every level.
struct SafeDIToolSeamHoleOnCycleTests: ~Copyable {
	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Rejected

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueACycleDeclaresAgain_whenHoleSitsOnInstantiatorCycleAndFillReceivesLabelOnlyIfAvailable() async {
		// Inline, the `A` that `B` forwarded `2` builds again hands `LiveApi` `count` 2; the fill would read `nil` again.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):11:5: error: `LiveApi` receives `count: Int?`, which `B` declares between where `Hub` instantiates `aBuilder: Instantiator<A>` and where `B` instantiates it again. Inline, the `A` built again receives `B`'s `count`, but the scope SafeDI hands the builder for `A`'s `api: any Api` (case `aBuilder_api` of `apiBuilder`) holds the same values at every level of that cycle. Give `count` on `B` another label, or make an @Instantiable declaration that fulfills `Api` one module `Feature` reads.
			\(fixtures["Feature"]!["B.swift"]):8:5: note: `B` declares `count: Int` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: Self.feature(b: ["@Forwarded public let count: Int"]),
					app: [Self.liveApi(["@Received(onlyIfAvailable: true) public let name: String?", "@Received(onlyIfAvailable: true) public let count: Int?"]), Self.root([])],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueACycleDeclaresAgain_whenFillRequiresLabelTheCallerAlsoProvides() async {
		// Inline, the `A` that `B` builds again hands `LiveApi` `B`'s `tag`; the fill would read `Root`'s at every level.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `tag: Tag`, which `B` declares between where `Hub` instantiates `aBuilder: Instantiator<A>` and where `B` instantiates it again. Inline, the `A` built again receives `B`'s `tag`, but the scope SafeDI hands the builder for `A`'s `api: any Api` (case `aBuilder_api` of `apiBuilder`) holds the same values at every level of that cycle. Give `tag` on `B` another label, or make an @Instantiable declaration that fulfills `Api` one module `Feature` reads.
			\(fixtures["Feature"]!["B.swift"]):8:5: note: `B` declares `tag: Tag` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [Self.tag] + Self.feature(b: ["@Forwarded public let tag: Tag"]),
					app: [Self.liveApi(["@Received public let tag: Tag"]), Self.root(["@Instantiated public let tag: Tag"])],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueACycleDeclaresAgain_whenFillRequiresLabelTheSeamCarriesFromAboveTheCycle() async {
		// `Hub`'s `tag` is a field of the scope struct, bound above the function the cycle closes on, so the fill would read
		// it at every level, where inline the `A` that `B` builds again hands `LiveApi` `B`'s.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `tag: Tag`, which `B` declares between where `Hub` instantiates `aBuilder: Instantiator<A>` and where `B` instantiates it again. Inline, the `A` built again receives `B`'s `tag`, but the scope SafeDI hands the builder for `A`'s `api: any Api` (case `aBuilder_api` of `apiBuilder`) holds the same values at every level of that cycle. Give `tag` on `B` another label, or make an @Instantiable declaration that fulfills `Api` one module `Feature` reads.
			\(fixtures["Feature"]!["B.swift"]):8:5: note: `B` declares `tag: Tag` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [Self.tag] + Self.feature(b: ["@Forwarded public let tag: Tag"], hub: ["@Instantiated public let tag: Tag"]),
					app: [Self.liveApi(["@Received public let tag: Tag"]), Self.root([])],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueACycleDeclaresAgain_whenHoleSitsOnLazyCycle() async {
		// `B`'s `a` closes on `Hub`'s `a`, a lazily instantiated `A`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `count: Int?`, which `B` declares between where `Hub` instantiates `a: LazilyInstantiated<A>` and where `B` instantiates it again. Inline, the `A` built again receives `B`'s `count`, but the scope SafeDI hands the builder for `A`'s `api: any Api` (case `a_api` of `apiBuilder`) holds the same values at every level of that cycle. Give `count` on `B` another label, or make an @Instantiable declaration that fulfills `Api` one module `Feature` reads.
			\(fixtures["Feature"]!["B.swift"]):8:5: note: `B` declares `count: Int` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						"public protocol Api {}",
						seamFixtureType(named: "A", declarations: ["@Instantiated public let api: any Api", "@Instantiated public let bBuilder: Instantiator<B>"]),
						seamFixtureType(named: "B", declarations: ["@Forwarded public let count: Int", "@Instantiated public let a: LazilyInstantiated<A>"]),
						seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let a: LazilyInstantiated<A>"]),
					],
					app: [Self.liveApi(["@Received(onlyIfAvailable: true) public let count: Int?"]), Self.root([])],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueACycleDeclaresAgain_whenSeamThatCallsHubPassesBuilderUp() async {
		// `Shell`, a seam of `Feature` too, calls `Hub` and cannot fill its builder, which it passes up to `Root`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `count: Int?`, which `B` declares between where `Hub` instantiates `aBuilder: Instantiator<A>` and where `B` instantiates it again. Inline, the `A` built again receives `B`'s `count`, but the scope SafeDI hands the builder for `A`'s `api: any Api` (case `aBuilder_api` of `apiBuilder`) holds the same values at every level of that cycle. Give `count` on `B` another label, or make an @Instantiable declaration that fulfills `Api` one module `Feature` reads.
			\(fixtures["Feature"]!["B.swift"]):8:5: note: `B` declares `count: Int` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: Self.feature(b: ["@Forwarded public let count: Int"]) + [
						seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated public let hub: Hub"]),
					],
					app: [
						Self.liveApi(["@Received(onlyIfAvailable: true) public let count: Int?"]),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let shell: Shell"]),
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueACycleDeclaresAgain_whenLabelIsParameterOfNestedCycleBetween() async {
		// `C` builds `B` again, so `B`'s function takes `count`, which `X` passes it first and `C` from then on. `B` receives
		// `count` from `X`, inside the function `B`'s `aBuilder` closes on, so that function takes no `count` and the scope
		// carries none. Inline, `LiveApi` makes `A`'s function take `count`, and the `A` that `B` builds again hands it the
		// `count` `B`'s function was passed; the fill would read `nil`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `count: Int?`, which `B`'s builder function takes as a parameter between where `Hub` instantiates `aBuilder: Instantiator<A>` and where `B` instantiates it again, because a cycle inside `B`'s tree passes it (`C` declares `count: Int`). Inline, the `A` built again receives the `count` that parameter is passed, but the scope SafeDI hands the builder for `A`'s `api: any Api` (case `aBuilder_api` of `apiBuilder`) holds the same values at every level of that cycle. Give `count` on `C` another label, or make an @Instantiable declaration that fulfills `Api` one module `Feature` reads.
			\(fixtures["Feature"]!["C.swift"]):8:5: note: `C` declares `count: Int` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						"public protocol Api {}",
						seamFixtureType(named: "A", declarations: ["@Instantiated public let api: any Api", "@Instantiated public let xBuilder: Instantiator<X>"]),
						seamFixtureType(named: "X", declarations: ["@Forwarded public let count: Int", "@Instantiated public let bBuilder: Instantiator<B>"]),
						seamFixtureType(named: "B", declarations: ["@Received(onlyIfAvailable: true) public let count: Int?", "@Instantiated public let cBuilder: Instantiator<C>", "@Instantiated public let aBuilder: Instantiator<A>"]),
						seamFixtureType(named: "C", declarations: ["@Forwarded public let count: Int", "@Instantiated public let bBuilder: Instantiator<B>"]),
						seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let aBuilder: Instantiator<A>"]),
					],
					app: [Self.liveApi(["@Received(onlyIfAvailable: true) public let count: Int?"]), Self.root([])],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueACycleDeclaresAgain_whenLabelIsParameterOfCycleNestedTwiceBetween() async {
		// `D` builds `C` again, so `C`'s function takes `count`, which `D` forwards, and `C` builds `B` again, so `B`'s
		// function takes `count` too, which `C`'s parameter passes it: the value `B`'s parameter carries is `D`'s. `B` receives
		// `count` from `X`, inside the function `B`'s `aBuilder` closes on, so that function takes no `count`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `count: Int?`, which `B`'s builder function takes as a parameter between where `Hub` instantiates `aBuilder: Instantiator<A>` and where `B` instantiates it again, because a cycle inside `B`'s tree passes it (`D` declares `count: Int`). Inline, the `A` built again receives the `count` that parameter is passed, but the scope SafeDI hands the builder for `A`'s `api: any Api` (case `aBuilder_api` of `apiBuilder`) holds the same values at every level of that cycle. Give `count` on `D` another label, or make an @Instantiable declaration that fulfills `Api` one module `Feature` reads.
			\(fixtures["Feature"]!["D.swift"]):8:5: note: `D` declares `count: Int` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						"public protocol Api {}",
						seamFixtureType(named: "A", declarations: ["@Instantiated public let api: any Api", "@Instantiated public let xBuilder: Instantiator<X>"]),
						seamFixtureType(named: "X", declarations: ["@Forwarded public let count: Int", "@Instantiated public let bBuilder: Instantiator<B>"]),
						seamFixtureType(named: "B", declarations: ["@Received(onlyIfAvailable: true) public let count: Int?", "@Instantiated public let cBuilder: Instantiator<C>", "@Instantiated public let aBuilder: Instantiator<A>"]),
						seamFixtureType(named: "C", declarations: ["@Received(onlyIfAvailable: true) public let count: Int?", "@Instantiated public let dBuilder: Instantiator<D>", "@Instantiated public let bBuilder: Instantiator<B>"]),
						seamFixtureType(named: "D", declarations: ["@Forwarded public let count: Int", "@Instantiated public let cBuilder: Instantiator<C>"]),
						seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let aBuilder: Instantiator<A>"]),
					],
					app: [Self.liveApi(["@Received(onlyIfAvailable: true) public let count: Int?"]), Self.root([])],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Accepted

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillBuildsInlineValues_whenFillReadsLabelDeclaredInsideFunctionTheCycleClosesOn() async throws {
		// The hole is `B`'s, inside the function `B`'s `aBuilder` closes on, and `B` forwards `count` at every level.
		let feature = [
			"public protocol Api {}",
			seamFixtureType(named: "A", declarations: ["@Forwarded public let name: String", "@Instantiated public let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", declarations: ["@Forwarded public let count: Int", "@Instantiated public let api: any Api", "@Instantiated public let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let aBuilder: Instantiator<A>"]),
		]
		let fulfiller = Self.liveApi(["@Received(onlyIfAvailable: true) public let name: String?", "@Received(onlyIfAvailable: true) public let count: Int?"])
		try await expectValuesEqualInlineBuild(
			feature: feature,
			fulfiller: fulfiller,
			root: Self.root([]),
			probe: DifferentialValueProbe(
				name: "B's api at each level",
				expression: """
				{ () -> [String] in
				    let a = Root().hub.aBuilder.instantiate("x")
				    let b = a.bBuilder.instantiate(2)
				    let b3 = b.aBuilder.instantiate("y").bBuilder.instantiate(3)
				    return [b.api, b3.api].map { "\\($0)" }
				}()
				""",
			),
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillBuildsInlineValues_whenFieldIsBoundFromParameterOfFunctionTheCycleClosesOn() async throws {
		// `A`'s `reader` requires `tag`, which `B` declares, so the function `A` is built with takes `tag`, and the field of
		// `A`'s `api` binds it from that parameter at every level.
		let feature = [
			"public protocol Api {}",
			Self.tag,
			seamFixtureType(named: "TagReader", declarations: ["@Received public let tag: Tag"]),
			seamFixtureType(named: "A", declarations: ["@Forwarded public let name: String", "@Instantiated public let reader: TagReader", "@Instantiated public let api: any Api", "@Instantiated public let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", declarations: ["@Forwarded public let tag: Tag", "@Instantiated public let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let tag: Tag", "@Instantiated public let aBuilder: Instantiator<A>"]),
		]
		try await expectValuesEqualInlineBuild(
			feature: feature,
			fulfiller: Self.liveApi(["@Received public let tag: Tag"]),
			root: Self.root([]),
			probe: Self.aApiAtEachLevel(forwarding: "Tag(value: \"two\")"),
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillBuildsInlineValues_whenFillRequiresLabelTheSeamTakesAsDeferredParameter() async throws {
		// `A`'s `reader` makes `tag` a parameter of the function the cycle closes on, which hides the `tag` `Hub` defers: the
		// field holds the parameter, `Root`'s at the first level and `B`'s where `B` builds `A` again, as inline hands it.
		let feature = [
			"public protocol Api {}",
			Self.tag,
			seamFixtureType(named: "TagReader", declarations: ["@Received public let tag: Tag"]),
			seamFixtureType(named: "A", declarations: ["@Forwarded public let name: String", "@Instantiated public let reader: TagReader", "@Instantiated public let api: any Api", "@Instantiated public let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", declarations: ["@Forwarded public let tag: Tag", "@Instantiated public let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let aBuilder: Instantiator<A>"]),
		]
		try await expectValuesEqualInlineBuild(
			feature: feature,
			fulfiller: Self.liveApi(["@Received public let tag: Tag"]),
			root: Self.root(["@Instantiated public let tag: Tag"]),
			probe: Self.aApiAtEachLevel(forwarding: "Tag(value: \"two\")"),
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillBuildsInlineValues_whenLabelIsParameterOfNestedCycleBetweenAndOfFunctionTheCycleClosesOn() async throws {
		// `C` builds `B` again, so `B`'s function takes `count`, which `C` forwards. `B` receives `count` from above `A`, so the
		// function `B`'s `aBuilder` closes on takes `count` too, and the field holds it: `nil` at the first level, and the
		// `count` `B`'s function was passed where `B` builds `A` again.
		let feature = [
			"public protocol Api {}",
			seamFixtureType(named: "A", declarations: ["@Instantiated public let api: any Api", "@Instantiated public let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", declarations: ["@Received(onlyIfAvailable: true) public let count: Int?", "@Instantiated public let cBuilder: Instantiator<C>", "@Instantiated public let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "C", declarations: ["@Forwarded public let count: Int", "@Instantiated public let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let aBuilder: Instantiator<A>"]),
		]
		try await expectValuesEqualInlineBuild(
			feature: feature,
			fulfiller: Self.liveApi(["@Received(onlyIfAvailable: true) public let count: Int?"]),
			root: Self.root([]),
			probe: DifferentialValueProbe(
				name: "A's api at each level",
				expression: """
				{ () -> [String] in
				    let b = Root().hub.aBuilder.instantiate().bBuilder.instantiate()
				    let b2 = b.cBuilder.instantiate(2).bBuilder.instantiate()
				    return [b.aBuilder.instantiate().api, b2.aBuilder.instantiate().api, b2.aBuilder.instantiate().bBuilder.instantiate().cBuilder.instantiate(3).bBuilder.instantiate().aBuilder.instantiate().api].map { "\\($0)" }
				}()
				""",
			),
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillBuildsInlineValues_whenLabelIsParameterOfCycleNestedTwiceBetweenAndOfFunctionTheCycleClosesOn() async throws {
		// `D` builds `C` again and `C` builds `B` again, so both functions take `count`, which `D` forwards. `B` receives
		// `count` from above `A`, so the function `B`'s `aBuilder` closes on takes `count` too, and the field holds it.
		let feature = [
			"public protocol Api {}",
			seamFixtureType(named: "A", declarations: ["@Instantiated public let api: any Api", "@Instantiated public let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", declarations: ["@Received(onlyIfAvailable: true) public let count: Int?", "@Instantiated public let cBuilder: Instantiator<C>", "@Instantiated public let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "C", declarations: ["@Received(onlyIfAvailable: true) public let count: Int?", "@Instantiated public let dBuilder: Instantiator<D>", "@Instantiated public let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "D", declarations: ["@Forwarded public let count: Int", "@Instantiated public let cBuilder: Instantiator<C>"]),
			seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let aBuilder: Instantiator<A>"]),
		]
		try await expectValuesEqualInlineBuild(
			feature: feature,
			fulfiller: Self.liveApi(["@Received(onlyIfAvailable: true) public let count: Int?"]),
			root: Self.root([]),
			probe: DifferentialValueProbe(
				name: "A's api at each level",
				expression: """
				{ () -> [String] in
				    let c = Root().hub.aBuilder.instantiate().bBuilder.instantiate().cBuilder.instantiate()
				    let b2 = c.dBuilder.instantiate(3).cBuilder.instantiate().bBuilder.instantiate()
				    return [c.bBuilder.instantiate().aBuilder.instantiate().api, b2.aBuilder.instantiate().api].map { "\\($0)" }
				}()
				""",
			),
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillBuildsInlineValues_whenCycleInsideSendableInstantiatorClosesOnFunctionBuiltByValue() async throws {
		// `Hub` builds `A` by value, and `B`, built in `A`'s `SendableInstantiator`, builds `A` again, which calls the function
		// `Hub`'s tree builds `A` with from a `@Sendable` closure: that function is `@Sendable`, so it starts a stage of the
		// place of `B`'s `api`, whose first stage the seam calls just before it.
		let feature = [
			"public protocol Api: Sendable {}",
			seamFixtureType(named: "A", declarations: ["@Instantiated public let bBuilder: SendableInstantiator<B>"], conformances: ", Sendable"),
			seamFixtureType(named: "B", declarations: ["@Instantiated public let api: any Api", "@Instantiated public let a: A"], conformances: ", Sendable"),
			seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let a: A"], conformances: ", Sendable"),
		]
		try await expectValuesEqualInlineBuild(
			feature: feature,
			fulfiller: Self.liveApi([]),
			root: Self.root([]),
			probe: DifferentialValueProbe(
				name: "B's api at each level",
				expression: """
				{ () -> [String] in
				    let b = Root().hub.a.bBuilder.instantiate()
				    return [b.api, b.a.bBuilder.instantiate().api].map { "\\($0)" }
				}()
				""",
			),
		)
	}

	// MARK: Fixtures

	/// `Api`, `A`, `B` and `Hub`:`B` declares `b`'s declarations before its `aBuilder`, and `Hub` declares `hub`'s before its
	/// own.
	private static func feature(b: [String], hub: [String] = []) -> [String] {
		[
			"public protocol Api {}",
			seamFixtureType(named: "A", declarations: ["@Forwarded public let name: String", "@Instantiated public let api: any Api", "@Instantiated public let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", declarations: b + ["@Instantiated public let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "Hub", isSeam: true, declarations: hub + ["@Instantiated public let aBuilder: Instantiator<A>"]),
		]
	}

	private static let tag = """
	@Instantiable
	public struct Tag: Instantiable, CustomStringConvertible {
	    public init() { value = "root" }
	    public init(value: String) { self.value = value }
	    public let value: String
	    public var description: String { value }
	}
	"""

	private static func liveApi(_ declarations: [String]) -> String {
		seamFixtureType(named: "LiveApi", declarations: declarations, conformances: ", Api")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Api.self])\n")
	}

	private static func root(_ declarations: [String]) -> String {
		seamFixtureType(named: "Root", isRoot: true, declarations: declarations + ["@Instantiated public let hub: Hub"])
	}

	/// The `api` of the `A` that `Hub` builds and of the one its `B`, forwarded `forwarded`, builds again.
	private static func aApiAtEachLevel(forwarding forwarded: String) -> DifferentialValueProbe {
		DifferentialValueProbe(
			name: "A's api at each level",
			expression: """
			{ () -> [String] in
			    let a = Root().hub.aBuilder.instantiate("x")
			    let again = a.bBuilder.instantiate(\(forwarded)).aBuilder.instantiate("y")
			    return [a.api, again.api].map { "\\($0)" }
			}()
			""",
		)
	}

	/// `Feature`, in package `Shop`, and `App`, in package `Other`, which imports it.
	private static func modules(feature: [String], app: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
	}

	/// Expects the build of `feature` and `App` holding `fulfiller` and `root` to compile and to construct the values the
	/// same graph builds with `fulfiller` in `Feature`, where no hole is left and the tree is built inline, for `probe`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectValuesEqualInlineBuild(
		feature: [String],
		fulfiller: String,
		root: String,
		probe: DifferentialValueProbe,
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let modules = Self.modules(feature: feature, app: [fulfiller, root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		guard compileVerificationIsEnabled else { return }
		let inlineModules = Self.modules(feature: feature + [fulfiller], app: [root])
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try expectDifferentialValuesAgree(
			feature: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: output, modules: modules),
			knownRight: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: inlineOutput, modules: inlineModules),
			probes: [probe],
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	private var filesToDelete: [URL]
}
