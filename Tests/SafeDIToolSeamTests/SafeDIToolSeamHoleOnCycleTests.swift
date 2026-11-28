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
			\(fixtures["App"]!["LiveApi.swift"]):11:5: error: `LiveApi` receives `count: Int?`, which `B` declares between where `Hub` instantiates `aBuilder: Instantiator<A>` and where `B` instantiates it again. Inline, the `A` built again receives `B`’s `count`, but SafeDI hands the builder for `A`’s `api: any Api` (`api` of `apiBuilder`) the same values at every level of that cycle. Declare `@Received(onlyIfAvailable: true) let count: Int?` on `A`, so each `A` receives the `count` of its own level and hands it on, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
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
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `tag: Tag`, which `B` declares between where `Hub` instantiates `aBuilder: Instantiator<A>` and where `B` instantiates it again. Inline, the `A` built again receives `B`’s `tag`, but SafeDI hands the builder for `A`’s `api: any Api` (`api` of `apiBuilder`) the same values at every level of that cycle. Declare `@Received let tag: Tag` on `A`, so each `A` receives the `tag` of its own level and hands it on, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
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
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `tag: Tag`, which `B` declares between where `Hub` instantiates `aBuilder: Instantiator<A>` and where `B` instantiates it again. Inline, the `A` built again receives `B`’s `tag`, but SafeDI hands the builder for `A`’s `api: any Api` (`api` of `apiBuilder`) the same values at every level of that cycle. Declare `@Received let tag: Tag` on `A`, so each `A` receives the `tag` of its own level and hands it on, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
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
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `count: Int?`, which `B` declares between where `Hub` instantiates `a: LazilyInstantiated<A>` and where `B` instantiates it again. Inline, the `A` built again receives `B`’s `count`, but SafeDI hands the builder for `A`’s `api: any Api` (`api` of `apiBuilder`) the same values at every level of that cycle. Declare `@Received(onlyIfAvailable: true) let count: Int?` on `A`, so each `A` receives the `count` of its own level and hands it on, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
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
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `count: Int?`, which `B` declares between where `Hub` instantiates `aBuilder: Instantiator<A>` and where `B` instantiates it again. Inline, the `A` built again receives `B`’s `count`, but SafeDI hands the builder for `A`’s `api: any Api` (`api` of `apiBuilder`) the same values at every level of that cycle. Declare `@Received(onlyIfAvailable: true) let count: Int?` on `A`, so each `A` receives the `count` of its own level and hands it on, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
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

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueACycleDeclaresAgain_whenSeamPassesUpPlaceOfCallInsideCycleOfItsOwnTree(throughSecondCycle: Bool) async {
		// `Shell` builds `W`, which calls `Hub` and whose cycle declares `l` again: `P` directly, or `P` in a second cycle
		// through `U`. `Shell` cannot fill `Hub`'s `api` and passes it up. Inline, the `W` built again beneath `P` hands its
		// `Hub`'s `api` `P`'s `l`; no function of `Shell`'s tree takes `l`, so the fill would read `Root`'s at every level.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `l: L`, \(throughSecondCycle
				? "which `U`’s builder function takes as a parameter between where `Shell` instantiates `wBuilder: Instantiator<W>` and where `U` instantiates it again, because a cycle inside `U`’s tree passes it (`P` declares `l: L`). Inline, the `W` built again receives the `l` that parameter is passed,"
				: "which `P` declares between where `Shell` instantiates `wBuilder: Instantiator<W>` and where `P` instantiates it again. Inline, the `W` built again receives `P`’s `l`,") but SafeDI hands the builder for `Hub`’s `api: any Api` (`api` of `apiBuilder`) the same values at every level of that cycle. Declare `@Received let l: L` on `Hub`, so each `W` passes its `Hub` the `l` of its own level, which the builder is then handed, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["P.swift"]):8:5: note: `P` declares `l: L` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: Self.shellCallingHubInsideCycle(throughSecondCycle: throughSecondCycle),
					app: [
						Self.liveApi(["@Received public let l: L"]),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let l: L", "@Instantiated public let shell: Shell"]),
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func presentedCycleReentryDeclarations_namesDeclarationCycleHandsTypeBuiltAgain_whenSeamCallIsInsideCycle() async throws {
		// The re-entries of the cycle around `Shell`'s call of `Hub` are a question of `Shell`'s graph, which names `P`'s `l`,
		// handed to the `W` built again, whose call builds `Hub`.
		let modules = Self.modules(
			feature: Self.shellCallingHubInsideCycle(throughSecondCycle: false),
			app: [Self.liveApi([]), seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let shell: Shell"])],
		)
		let (stream, continuation) = AsyncStream.makeStream(of: SeamSignature.Places.Observation.self)
		_ = try await SeamPlaceLevels.$observer.withValue(TaskLocalFunction { placeLevels in
			if let observation = placeLevels.placesObservation, observation.seamType.asSource == "Shell" {
				continuation.yield(observation)
			}
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		continuation.finish()
		var observationOfShell: SeamSignature.Places.Observation?
		for await observation in stream {
			observationOfShell = observation
		}
		let shell = try #require(observationOfShell)
		let caseIndex = try #require(shell.places.cases.indices.first { shell.places.cases[$0].passedUp != nil })
		let query = SeamSignature.Places.Query(of: shell.places, calledPlaces: shell.calledPlaces(of:))
		let declarations = query.presentedCycleReentryDeclarations(ofLabel: "l", reading: .callersOwn, at: caseIndex)
		#expect(declarations.map { "\($0.declaringType.asSource) declares \($0.property.asSource); \($0.reenteringType.asSource) closes on \($0.closedOnProperty.asSource); builder of \($0.calledSeamType?.asSource ?? "no seam")" } == ["P declares l: L; P closes on wBuilder: Instantiator<W>; builder of Hub"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueACycleDeclaresAgain_whenSecondSeamPassesOnPlacePassedUpFromInsideCycle() async {
		// `Outer`, a seam too, calls `Shell` and passes the place on: the copy keeps what `Shell`'s cycle declares again.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `l: L`, which `P` declares between where `Shell` instantiates `wBuilder: Instantiator<W>` and where `P` instantiates it again. Inline, the `W` built again receives `P`’s `l`, but SafeDI hands the builder for `Hub`’s `api: any Api` (`api` of `apiBuilder`) the same values at every level of that cycle. Declare `@Received let l: L` on `Hub`, so each `W` passes its `Hub` the `l` of its own level, which the builder is then handed, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["P.swift"]):8:5: note: `P` declares `l: L` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						"public protocol Api {}",
						seamFixtureType(named: "L", isFinalClass: true, declarations: []),
						seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let api: any Api"]),
						seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated public let wBuilder: Instantiator<W>"]),
						seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let shell: Shell"]),
						seamFixtureType(named: "W", declarations: ["@Instantiated public let hub: Hub", "@Instantiated public let pBuilder: Instantiator<P>"]),
						seamFixtureType(named: "P", declarations: ["@Instantiated public let l: L", "@Instantiated public let wBuilder: Instantiator<W>"]),
					],
					app: [
						Self.liveApi(["@Received public let l: L"]),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let l: L", "@Instantiated public let outer: Outer"]),
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillBuildsInlineValues_whenSeamCalledInsideCycleReceivesLabelItsPassedUpPlacesFillReads(callsInsideSendableFunction: Bool) async throws {
		// The remedy of the error above: `Hub` receives `l`, so `W`'s function takes it, each call of `Hub` is passed the
		// `l` of its level, and `Hub`'s scope carries it to the fill. With every type `Sendable` and every builder a
		// `SendableInstantiator`, each call of `Hub` is made inside a `@Sendable` function, which the remedy holds for too.
		let instantiator = callsInsideSendableFunction ? "SendableInstantiator" : "Instantiator"
		let conformances = callsInsideSendableFunction ? ", Sendable" : ""
		try await expectValuesEqualInlineBuild(
			feature: [
				"public protocol Api\(callsInsideSendableFunction ? ": Sendable" : "") {}",
				seamFixtureType(named: "L", isFinalClass: true, declarations: [], conformances: conformances),
				seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Received public let l: L", "@Instantiated public let api: any Api"], conformances: conformances),
				seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated public let wBuilder: \(instantiator)<W>"], conformances: conformances),
				seamFixtureType(named: "W", declarations: ["@Instantiated public let hub: Hub", "@Instantiated public let pBuilder: \(instantiator)<P>"], conformances: conformances),
				seamFixtureType(named: "P", declarations: ["@Instantiated public let l: L", "@Instantiated public let wBuilder: \(instantiator)<W>"], conformances: conformances),
			],
			fulfiller: Self.liveApi(["@Received public let l: L"], conformances: conformances),
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let l: L", "@Instantiated public let shell: Shell"]),
			probe: DifferentialValueProbe(
				name: "whose l the api of each W's Hub holds",
				expression: """
				{ () -> [String] in
				    let root = Root()
				    let w = root.shell.wBuilder.instantiate()
				    let p = w.pBuilder.instantiate()
				    let wAgain = p.wBuilder.instantiate()
				    func l(of w: W) -> L { (w.hub.api as! LiveApi).l }
				    return ["\\(l(of: w) === root.l)", "\\(l(of: wAgain) === p.l)", "\\(l(of: wAgain) === root.l)"]
				}()
				""",
			),
		)
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
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `count: Int?`, which `B`’s builder function takes as a parameter between where `Hub` instantiates `aBuilder: Instantiator<A>` and where `B` instantiates it again, because a cycle inside `B`’s tree passes it (`C` declares `count: Int`). Inline, the `A` built again receives the `count` that parameter is passed, but SafeDI hands the builder for `A`’s `api: any Api` (`api` of `apiBuilder`) the same values at every level of that cycle. Declare `@Received(onlyIfAvailable: true) let count: Int?` on `A`, so each `A` receives the `count` of its own level and hands it on, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
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
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `count: Int?`, which `B`’s builder function takes as a parameter between where `Hub` instantiates `aBuilder: Instantiator<A>` and where `B` instantiates it again, because a cycle inside `B`’s tree passes it (`D` declares `count: Int`). Inline, the `A` built again receives the `count` that parameter is passed, but SafeDI hands the builder for `A`’s `api: any Api` (`api` of `apiBuilder`) the same values at every level of that cycle. Declare `@Received(onlyIfAvailable: true) let count: Int?` on `A`, so each `A` receives the `count` of its own level and hands it on, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
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

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueACycleDeclaresAgain_whenTangleOfCyclesBuildsTypeAgainThroughFunctionThatTakesNoParameter() async {
		// The graph fuzzer's seed 605, reduced, by the ruling that a seam's tree hands a place the values inline does, never
		// the caller's: `Hub` builds `T` and `C`, each of which builds the other, a tangle no type always encloses. Inline,
		// the `T` that `C` builds again inside `Hub`'s `T` hands `LiveApi` `C`'s `mark`; nothing in `Feature` receives `mark`,
		// so the function that builds `T` takes no parameter, and the fill, handed the chain of the first build, would read
		// `Root`'s nothing.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `mark: Mark?`, which `C` declares between where `Hub` instantiates `tBuilder: Instantiator<T>` and where `C` instantiates it again. Inline, the `T` built again receives `C`’s `mark`, but SafeDI hands the builder for `T`’s `api: any Api` (`api` of `apiBuilder`) the same values at every level of that cycle. Declare `@Received(onlyIfAvailable: true) let mark: Mark?` on `T`, so each `T` receives the `mark` of its own level and hands it on, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["C.swift"]):8:5: note: `C` declares `mark: Mark` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: Self.tangle(t: []),
					app: [Self.liveApi(["@Received(onlyIfAvailable: true) public let mark: Mark?"]), Self.root([])],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueACycleDeclaresAgain_whenCycleNestedBetweenDeclaresLabelNoFunctionTakes() async {
		// `U` builds `W` again, and `P` builds `U` again and declares `l`. Nothing in `Feature` receives `l`, so no builder
		// function takes it, and no declaration on the path from `W` to the `W` built again declares it. Inline, `LiveApi`
		// makes the functions of `W` and `U` take `l`, and the `W` that the `U` beneath `P` builds again hands it `P`'s; the
		// fill would read `Hub`'s at every level.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `l: L`, which `U`’s builder function takes as a parameter between where `Hub` instantiates `wBuilder: Instantiator<W>` and where `U` instantiates it again, because a cycle inside `U`’s tree passes it (`P` declares `l: L`). Inline, the `W` built again receives the `l` that parameter is passed, but SafeDI hands the builder for `V`’s `api: any Api` (`api` of `apiBuilder`) the same values at every level of that cycle. Declare `@Received let l: L` on `W`, so each `W` receives the `l` of its own level and hands it on, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["P.swift"]):8:5: note: `P` declares `l: L` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: Self.typeBuiltAgainThroughSecondCycle(w: []),
					app: [Self.liveApi(["@Received public let l: L"]), Self.root([])],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueACycleDeclaresAgain_whenLabelIsDeclaredInCycleNestedInsideCycleNestedBetween(declaresAfterCloser: Bool) async {
		// Three cycles, one inside another: `U` builds `W` again, `T` builds `U` again, and `P` builds `T` again and declares
		// `l`. The path from `U` to the `U` built again declares no `l`: it reaches `U` only as what the cycle on `T`, a scope
		// on that path, declares. `T` builds `U` again before or after `P`, the order the paths are read in.
		let tDeclares = ["@Instantiated public let uBuilder: Instantiator<U>", "@Instantiated public let pBuilder: Instantiator<P>"]
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `l: L`, which `U`’s builder function takes as a parameter between where `Hub` instantiates `wBuilder: Instantiator<W>` and where `U` instantiates it again, because a cycle inside `U`’s tree passes it (`P` declares `l: L`). Inline, the `W` built again receives the `l` that parameter is passed, but SafeDI hands the builder for `V`’s `api: any Api` (`api` of `apiBuilder`) the same values at every level of that cycle. Declare `@Received let l: L` on `W`, so each `W` receives the `l` of its own level and hands it on, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["P.swift"]):8:5: note: `P` declares `l: L` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						"public protocol Api {}",
						seamFixtureType(named: "L", isFinalClass: true, declarations: []),
						seamFixtureType(named: "W", declarations: ["@Instantiated public let uBuilder: Instantiator<U>", "@Instantiated public let vBuilder: Instantiator<V>"]),
						seamFixtureType(named: "U", declarations: ["@Instantiated public let tBuilder: Instantiator<T>", "@Instantiated public let wBuilder: Instantiator<W>"]),
						seamFixtureType(named: "T", declarations: declaresAfterCloser ? tDeclares : tDeclares.reversed()),
						seamFixtureType(named: "P", declarations: ["@Instantiated public let l: L", "@Instantiated public let tBuilder: Instantiator<T>"]),
						seamFixtureType(named: "V", declarations: ["@Instantiated public let api: any Api"]),
						seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let l: L", "@Instantiated public let wBuilder: Instantiator<W>"]),
					],
					app: [Self.liveApi(["@Received public let l: L"]), Self.root([])],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueACycleDeclaresAgain_whenOnlyLaterPathThroughSharedScopeDeclaresLabel() async {
		// `B` builds `W` again itself, a first path that declares nothing, and through `C`, which declares `l`. `A`, above
		// `B`, reads `B`'s paths once and reports the later one's `l`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `l: L`, which `C` declares between where `Hub` instantiates `wBuilder: Instantiator<W>` and where `C` instantiates it again. Inline, the `W` built again receives `C`’s `l`, but SafeDI hands the builder for `W`’s `api: any Api` (`api` of `apiBuilder`) the same values at every level of that cycle. Declare `@Received let l: L` on `W`, so each `W` receives the `l` of its own level and hands it on, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["C.swift"]):8:5: note: `C` declares `l: L` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						"public protocol Api {}",
						seamFixtureType(named: "L", isFinalClass: true, declarations: []),
						seamFixtureType(named: "W", declarations: ["@Instantiated public let api: any Api", "@Instantiated public let aBuilder: Instantiator<A>"]),
						seamFixtureType(named: "A", declarations: ["@Instantiated public let bBuilder: Instantiator<B>"]),
						seamFixtureType(named: "B", declarations: ["@Instantiated public let wBuilder: Instantiator<W>", "@Instantiated public let cBuilder: Instantiator<C>"]),
						seamFixtureType(named: "C", declarations: ["@Instantiated public let l: L", "@Instantiated public let wBuilder: Instantiator<W>"]),
						seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let l: L", "@Instantiated public let wBuilder: Instantiator<W>"]),
					],
					app: [Self.liveApi(["@Received public let l: L"]), Self.root([])],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueACycleDeclaresAgain_whenCycleNestedBetweenIsClosedThroughSendableInstantiators() async {
		// The graph of the test above with every type `Sendable` and every builder a `SendableInstantiator`, so the place
		// is in the `@Sendable` family: the read is rejected, and no receive on `W` is offered, since `V`'s `@Sendable` function hands
		// the place nothing `W`'s function binds.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `l: L`, which `U`’s builder function takes as a parameter between where `Hub` instantiates `wBuilder: SendableInstantiator<W>` and where `U` instantiates it again, because a cycle inside `U`’s tree passes it (`P` declares `l: L`). Inline, the `W` built again receives the `l` that parameter is passed, but SafeDI hands the builder for `V`’s `api: any Api` (`api` of `apiSendableBuilder`) the same values at every level of that cycle. Declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["P.swift"]):8:5: note: `P` declares `l: L` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: Self.typeBuiltAgainThroughSecondCycle(w: [], instantiator: "SendableInstantiator", conformances: ", Sendable"),
					app: [Self.liveApi(["@Received public let l: L"], conformances: ", Sendable"), Self.root([])],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Accepted

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillBuildsInlineValues_whenTypeBuiltAgainThroughSecondCycleReceivesLabelTheFillReads() async throws {
		// The remedy of the error above: `W` receives `l`, so the functions of `W` and `U` take it, `W`'s level carries it,
		// and the `W` that the `U` beneath `P` builds again hands `LiveApi` `P`'s `l`.
		try await expectValuesEqualInlineBuild(
			feature: Self.typeBuiltAgainThroughSecondCycle(w: ["@Received public let l: L"]),
			fulfiller: Self.liveApi(["@Received public let l: L"]),
			root: Self.root([]),
			probe: DifferentialValueProbe(
				name: "whose l the api of each W holds",
				expression: """
				{ () -> [String] in
				    let hub = Root().hub
				    let w = hub.wBuilder.instantiate()
				    let p = w.uBuilder.instantiate().pBuilder.instantiate()
				    let wAgain = p.uBuilder.instantiate().wBuilder.instantiate()
				    func l(of w: W) -> L { (w.vBuilder.instantiate().api as! LiveApi).l }
				    return ["\\(l(of: w) === hub.l)", "\\(l(of: wAgain) === p.l)", "\\(l(of: wAgain) === hub.l)"]
				}()
				""",
			),
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillBuildsInlineValues_whenOnlyOneBuildOfTypeTakesTheCycleParameterTheFillReads() async throws {
		// The graph fuzzer's seed 605, reduced, by the ruling that a seam's tree hands a place the values inline does, never
		// the caller's. `Hub` builds `T` and `C`, each of which builds the other, a tangle no type always encloses. `T`'s
		// `reader` receives `mark`, so the function that builds `Hub`'s `T` takes it as a cycle parameter, while the `T` that
		// `Hub`'s `C` builds reads `C`'s from above. `T`'s level carries `mark` in the parameter's form: bound from the
		// parameter where the function takes it, and from `C`'s `mark` where it does not, as each `T`'s tree reads it inline.
		try await expectValuesEqualInlineBuild(
			feature: Self.tangle(t: ["@Instantiated public let reader: MarkReader"]) + [
				seamFixtureType(named: "MarkReader", declarations: ["@Received(onlyIfAvailable: true) public let mark: Mark?"]),
			],
			fulfiller: Self.liveApi(["@Received(onlyIfAvailable: true) public let mark: Mark?"]),
			root: Self.root([]),
			probe: DifferentialValueProbe(
				name: "T's api at each build",
				expression: """
				{ () -> [String] in
				    let hub = Root().hub
				    let t = hub.tBuilder.instantiate()
				    return [t.api, t.cBuilder.instantiate().tBuilder.instantiate().api, hub.cBuilder.instantiate().tBuilder.instantiate().api].map { "\\($0)" }
				}()
				""",
			),
			expectedFeatureFile: (name: "Feature.swift", contents: """
			extension Hub {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
			        public let tBuilder: (LazilyInstantiated<Mark?>) -> __safeDI_ApiCarrier_T<__safeDI_Built>
			        public let cBuilder: (LazilyInstantiated<Mark?>, Instantiator<T>) -> __safeDI_ApiCarrier_C<__safeDI_Built>

			        public init(tBuilder: @escaping (LazilyInstantiated<Mark?>) -> __safeDI_ApiCarrier_T<__safeDI_Built>, cBuilder: @escaping (LazilyInstantiated<Mark?>, Instantiator<T>) -> __safeDI_ApiCarrier_C<__safeDI_Built>) {
			            self.tBuilder = tBuilder
			            self.cBuilder = cBuilder
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_T<__safeDI_Built> {
			        public let cBuilder: (Mark?, MarkReader) -> __safeDI_ApiCarrier_C<__safeDI_Built>
			        public let api: (Mark?, MarkReader, Instantiator<C>) -> __safeDI_Built

			        public init(cBuilder: @escaping (Mark?, MarkReader) -> __safeDI_ApiCarrier_C<__safeDI_Built>, api: @escaping (Mark?, MarkReader, Instantiator<C>) -> __safeDI_Built) {
			            self.cBuilder = cBuilder
			            self.api = api
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_C<__safeDI_Built> {
			        public let tBuilder: (Mark) -> __safeDI_ApiCarrier_T<__safeDI_Built>

			        public init(tBuilder: @escaping (Mark) -> __safeDI_ApiCarrier_T<__safeDI_Built>) {
			            self.tBuilder = tBuilder
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_mark __safeDI_mark_: @autoclosure @escaping () -> Mark?, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
			        let mark = LazilyInstantiated<Mark?>(__safeDI_mark_)
			        let __safeDI_apiBuilder_tBuilder = __safeDI_apiBuilder.tBuilder(mark)
			        @inline(never) func __safeDI_tBuilder(mark: Mark?) -> T {
			            let reader = MarkReader(mark: mark)
			            @inline(never) func __safeDI_cBuilder() -> C {
			                let mark = Mark()
			                let tBuilder = Instantiator<T> {
			                    __safeDI_tBuilder(mark: mark)
			                }
			                return C(mark: mark, tBuilder: tBuilder)
			            }
			            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			            let api: any Api = __safeDI_apiBuilder_tBuilder.api(mark, reader, cBuilder)
			            return T(reader: reader, cBuilder: cBuilder, api: api)
			        }
			        let tBuilder = Instantiator<T> {
			            __safeDI_tBuilder(mark: mark.instance)
			        }
			        let __safeDI_apiBuilder_cBuilder = __safeDI_apiBuilder.cBuilder(mark, tBuilder)
			        @inline(never) func __safeDI_cBuilder() -> C {
			            let mark = Mark()
			            let __safeDI_apiBuilder_tBuilder = __safeDI_apiBuilder_cBuilder.tBuilder(mark)
			            @inline(never) func __safeDI_tBuilder() -> T {
			                let reader = MarkReader(mark: mark)
			                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                let api: any Api = __safeDI_apiBuilder_tBuilder.api(mark, reader, cBuilder)
			                return T(reader: reader, cBuilder: cBuilder, api: api)
			            }
			            let tBuilder = Instantiator<T>(__safeDI_tBuilder)
			            return C(mark: mark, tBuilder: tBuilder)
			        }
			        let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			        self.init(tBuilder: tBuilder, cBuilder: cBuilder)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_FA5369582812EEA1 {}
			}
			"""),
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_apiBuilder_Hub() -> Hub.__safeDI_ApiCarrier<any Api> {
			            .init(tBuilder: { values_mark in __safeDI_apiBuilder_Hub_T_Scope() }, cBuilder: { values_mark, values_tBuilder in __safeDI_apiBuilder_Hub_C_Scope() })
			        }
			        func __safeDI_apiBuilder_Hub_T_Scope() -> Hub.__safeDI_ApiCarrier_T<any Api> {
			            .init(
			                cBuilder: { values_mark, values_reader in __safeDI_apiBuilder_Hub_C_Scope() },
			                api: { scope_mark, scope_reader, scope_cBuilder in
			                    let mark = scope_mark
			                    let api: any Api = LiveApi(mark: mark)
			                    return api
			                }
			            )
			        }
			        func __safeDI_apiBuilder_Hub_C_Scope() -> Hub.__safeDI_ApiCarrier_C<any Api> {
			            .init(tBuilder: { values_mark in __safeDI_apiBuilder_Hub_T_Scope() })
			        }
			        func __safeDI_hub() -> Hub {
			            _ = Hub.__safeDI_Hub_FA5369582812EEA1.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Hub(__safeDI_mark: nil, __safeDI_apiBuilder: __safeDI_apiBuilder_Hub())
			        }
			        let hub: Hub = __safeDI_hub()
			        self.init(hub: hub)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillBuildsInlineValues_whenBuildByValueBesideTangleReadsCycleParameterFromSeamsDeferredParameter() async throws {
		// Seed 605's tangle, where `Hub` also builds `T` by value and `Root` instantiates `mark`, which `Hub` defers. The
		// function that builds `Hub`'s `t` takes no parameter, so `T`'s level binds `mark` as `t`'s tree reads it there: the
		// instance of the deferred parameter, as `reader` reads it.
		try await expectValuesEqualInlineBuild(
			feature: Self.tangle(t: ["@Instantiated public let reader: MarkReader"], hub: ["@Instantiated public let t: T"], markIsFinalClass: true) + [
				seamFixtureType(named: "MarkReader", declarations: ["@Received public let mark: Mark"]),
			],
			fulfiller: Self.liveApi(["@Received public let mark: Mark"]),
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let mark: Mark", "@Instantiated public let hub: Hub"]),
			probe: DifferentialValueProbe(
				name: "T's api and reader at each build",
				expression: """
				{ () -> [Any] in
				    let root = Root()
				    let hub = root.hub
				    let c = hub.cBuilder.instantiate()
				    let tc = hub.t.cBuilder.instantiate()
				    return [root.mark, hub.t, tc, tc.tBuilder.instantiate(), hub.tBuilder.instantiate(), c, c.tBuilder.instantiate()]
				}()
				""",
			),
			expectedFeatureFile: (name: "Feature.swift", contents: """
			extension Hub {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
			        public let tBuilder: (LazilyInstantiated<Mark>) -> __safeDI_ApiCarrier_T<__safeDI_Built>
			        public let cBuilder: (LazilyInstantiated<Mark>, Instantiator<T>) -> __safeDI_ApiCarrier_C<__safeDI_Built>
			        public let t: (LazilyInstantiated<Mark>, Instantiator<T>, Instantiator<C>) -> __safeDI_ApiCarrier_T<__safeDI_Built>

			        public init(tBuilder: @escaping (LazilyInstantiated<Mark>) -> __safeDI_ApiCarrier_T<__safeDI_Built>, cBuilder: @escaping (LazilyInstantiated<Mark>, Instantiator<T>) -> __safeDI_ApiCarrier_C<__safeDI_Built>, t: @escaping (LazilyInstantiated<Mark>, Instantiator<T>, Instantiator<C>) -> __safeDI_ApiCarrier_T<__safeDI_Built>) {
			            self.tBuilder = tBuilder
			            self.cBuilder = cBuilder
			            self.t = t
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_T<__safeDI_Built> {
			        public let cBuilder: (Mark, MarkReader) -> __safeDI_ApiCarrier_C<__safeDI_Built>
			        public let api: (Mark, MarkReader, Instantiator<C>) -> __safeDI_Built

			        public init(cBuilder: @escaping (Mark, MarkReader) -> __safeDI_ApiCarrier_C<__safeDI_Built>, api: @escaping (Mark, MarkReader, Instantiator<C>) -> __safeDI_Built) {
			            self.cBuilder = cBuilder
			            self.api = api
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_C<__safeDI_Built> {
			        public let tBuilder: (Mark) -> __safeDI_ApiCarrier_T<__safeDI_Built>

			        public init(tBuilder: @escaping (Mark) -> __safeDI_ApiCarrier_T<__safeDI_Built>) {
			            self.tBuilder = tBuilder
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_mark __safeDI_mark_: @autoclosure @escaping () -> Mark, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
			        let mark = LazilyInstantiated<Mark>(__safeDI_mark_)
			        let __safeDI_apiBuilder_tBuilder = __safeDI_apiBuilder.tBuilder(mark)
			        @inline(never) func __safeDI_tBuilder(mark: Mark) -> T {
			            let reader = MarkReader(mark: mark)
			            @inline(never) func __safeDI_cBuilder() -> C {
			                let mark = Mark()
			                let tBuilder = Instantiator<T> {
			                    __safeDI_tBuilder(mark: mark)
			                }
			                return C(mark: mark, tBuilder: tBuilder)
			            }
			            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			            let api: any Api = __safeDI_apiBuilder_tBuilder.api(mark, reader, cBuilder)
			            return T(reader: reader, cBuilder: cBuilder, api: api)
			        }
			        let tBuilder = Instantiator<T> {
			            __safeDI_tBuilder(mark: mark.instance)
			        }
			        let __safeDI_apiBuilder_cBuilder = __safeDI_apiBuilder.cBuilder(mark, tBuilder)
			        @inline(never) func __safeDI_cBuilder() -> C {
			            let mark = Mark()
			            let __safeDI_apiBuilder_tBuilder = __safeDI_apiBuilder_cBuilder.tBuilder(mark)
			            @inline(never) func __safeDI_tBuilder() -> T {
			                let reader = MarkReader(mark: mark)
			                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                let api: any Api = __safeDI_apiBuilder_tBuilder.api(mark, reader, cBuilder)
			                return T(reader: reader, cBuilder: cBuilder, api: api)
			            }
			            let tBuilder = Instantiator<T>(__safeDI_tBuilder)
			            return C(mark: mark, tBuilder: tBuilder)
			        }
			        let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			        let __safeDI_apiBuilder_t = __safeDI_apiBuilder.t(mark, tBuilder, cBuilder)
			        @inline(never) func __safeDI_t() -> T {
			            let reader = MarkReader(mark: mark.instance)
			            let __safeDI_apiBuilder_cBuilder = __safeDI_apiBuilder_t.cBuilder(mark.instance, reader)
			            @inline(never) func __safeDI_cBuilder() -> C {
			                let mark = Mark()
			                let __safeDI_apiBuilder_tBuilder = __safeDI_apiBuilder_cBuilder.tBuilder(mark)
			                @inline(never) func __safeDI_tBuilder() -> T {
			                    let reader = MarkReader(mark: mark)
			                    let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                    let api: any Api = __safeDI_apiBuilder_tBuilder.api(mark, reader, cBuilder)
			                    return T(reader: reader, cBuilder: cBuilder, api: api)
			                }
			                let tBuilder = Instantiator<T>(__safeDI_tBuilder)
			                return C(mark: mark, tBuilder: tBuilder)
			            }
			            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			            let api: any Api = __safeDI_apiBuilder_t.api(mark.instance, reader, cBuilder)
			            return T(reader: reader, cBuilder: cBuilder, api: api)
			        }
			        let t: T = __safeDI_t()
			        self.init(tBuilder: tBuilder, cBuilder: cBuilder, t: t)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_5ADBAC71ED742FF9 {}
			}
			"""),
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_apiBuilder_Hub() -> Hub.__safeDI_ApiCarrier<any Api> {
			            .init(tBuilder: { values_mark in __safeDI_apiBuilder_Hub_T_Scope() }, cBuilder: { values_mark, values_tBuilder in __safeDI_apiBuilder_Hub_C_Scope() }, t: { values_mark, values_tBuilder, values_cBuilder in __safeDI_apiBuilder_Hub_T_Scope() })
			        }
			        func __safeDI_apiBuilder_Hub_T_Scope() -> Hub.__safeDI_ApiCarrier_T<any Api> {
			            .init(
			                cBuilder: { values_mark, values_reader in __safeDI_apiBuilder_Hub_C_Scope() },
			                api: { scope_mark, scope_reader, scope_cBuilder in
			                    let mark = scope_mark
			                    let api: any Api = LiveApi(mark: mark)
			                    return api
			                }
			            )
			        }
			        func __safeDI_apiBuilder_Hub_C_Scope() -> Hub.__safeDI_ApiCarrier_C<any Api> {
			            .init(tBuilder: { values_mark in __safeDI_apiBuilder_Hub_T_Scope() })
			        }
			        let mark = Mark()
			        func __safeDI_hub() -> Hub {
			            _ = Hub.__safeDI_Hub_5ADBAC71ED742FF9.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Hub(__safeDI_mark: mark, __safeDI_apiBuilder: __safeDI_apiBuilder_Hub())
			        }
			        let hub: Hub = __safeDI_hub()
			        self.init(mark: mark, hub: hub)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillBuildsInlineValues_whenBuildByValueBesideTangleReadsCycleParameterFromLazilyInstantiatedDeclaration() async throws {
		// Seed 605's tangle, where `Hub` also builds `T` by value and declares `mark` lazily. The function that builds `Hub`'s
		// `t` takes no parameter, so `T`'s level binds `mark` as `t`'s tree reads it there: the instance of `Hub`'s
		// `LazilyInstantiated`, as `reader` reads it.
		try await expectValuesEqualInlineBuild(
			feature: Self.tangle(t: ["@Instantiated public let reader: MarkReader"], hub: ["@Instantiated public let mark: LazilyInstantiated<Mark>", "@Instantiated public let t: T"], markIsFinalClass: true) + [
				seamFixtureType(named: "MarkReader", declarations: ["@Received public let mark: Mark"]),
			],
			fulfiller: Self.liveApi(["@Received public let mark: Mark"]),
			root: Self.root([]),
			probe: DifferentialValueProbe(
				name: "T's api and reader at each build",
				expression: """
				{ () -> [Any] in
				    let hub = Root().hub
				    let c = hub.cBuilder.instantiate()
				    let tc = hub.t.cBuilder.instantiate()
				    return [hub.mark.instance, hub.t, tc, tc.tBuilder.instantiate(), hub.tBuilder.instantiate(), c, c.tBuilder.instantiate()]
				}()
				""",
			),
			expectedFeatureFile: (name: "Feature.swift", contents: """
			extension Hub {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
			        public let tBuilder: (LazilyInstantiated<Mark>) -> __safeDI_ApiCarrier_T<__safeDI_Built>
			        public let cBuilder: (LazilyInstantiated<Mark>, Instantiator<T>) -> __safeDI_ApiCarrier_C<__safeDI_Built>
			        public let t: (LazilyInstantiated<Mark>, Instantiator<T>, Instantiator<C>) -> __safeDI_ApiCarrier_T<__safeDI_Built>

			        public init(tBuilder: @escaping (LazilyInstantiated<Mark>) -> __safeDI_ApiCarrier_T<__safeDI_Built>, cBuilder: @escaping (LazilyInstantiated<Mark>, Instantiator<T>) -> __safeDI_ApiCarrier_C<__safeDI_Built>, t: @escaping (LazilyInstantiated<Mark>, Instantiator<T>, Instantiator<C>) -> __safeDI_ApiCarrier_T<__safeDI_Built>) {
			            self.tBuilder = tBuilder
			            self.cBuilder = cBuilder
			            self.t = t
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_T<__safeDI_Built> {
			        public let cBuilder: (Mark, MarkReader) -> __safeDI_ApiCarrier_C<__safeDI_Built>
			        public let api: (Mark, MarkReader, Instantiator<C>) -> __safeDI_Built

			        public init(cBuilder: @escaping (Mark, MarkReader) -> __safeDI_ApiCarrier_C<__safeDI_Built>, api: @escaping (Mark, MarkReader, Instantiator<C>) -> __safeDI_Built) {
			            self.cBuilder = cBuilder
			            self.api = api
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_C<__safeDI_Built> {
			        public let tBuilder: (Mark) -> __safeDI_ApiCarrier_T<__safeDI_Built>

			        public init(tBuilder: @escaping (Mark) -> __safeDI_ApiCarrier_T<__safeDI_Built>) {
			            self.tBuilder = tBuilder
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
			        @inline(never) func __safeDI_mark() -> Mark {
			            Mark()
			        }
			        let mark = LazilyInstantiated<Mark>(__safeDI_mark)
			        let __safeDI_apiBuilder_tBuilder = __safeDI_apiBuilder.tBuilder(mark)
			        @inline(never) func __safeDI_tBuilder(mark: Mark) -> T {
			            let reader = MarkReader(mark: mark)
			            @inline(never) func __safeDI_cBuilder() -> C {
			                let mark = Mark()
			                let tBuilder = Instantiator<T> {
			                    __safeDI_tBuilder(mark: mark)
			                }
			                return C(mark: mark, tBuilder: tBuilder)
			            }
			            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			            let api: any Api = __safeDI_apiBuilder_tBuilder.api(mark, reader, cBuilder)
			            return T(reader: reader, cBuilder: cBuilder, api: api)
			        }
			        let tBuilder = Instantiator<T> {
			            __safeDI_tBuilder(mark: mark.instance)
			        }
			        let __safeDI_apiBuilder_cBuilder = __safeDI_apiBuilder.cBuilder(mark, tBuilder)
			        @inline(never) func __safeDI_cBuilder() -> C {
			            let mark = Mark()
			            let __safeDI_apiBuilder_tBuilder = __safeDI_apiBuilder_cBuilder.tBuilder(mark)
			            @inline(never) func __safeDI_tBuilder() -> T {
			                let reader = MarkReader(mark: mark)
			                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                let api: any Api = __safeDI_apiBuilder_tBuilder.api(mark, reader, cBuilder)
			                return T(reader: reader, cBuilder: cBuilder, api: api)
			            }
			            let tBuilder = Instantiator<T>(__safeDI_tBuilder)
			            return C(mark: mark, tBuilder: tBuilder)
			        }
			        let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			        let __safeDI_apiBuilder_t = __safeDI_apiBuilder.t(mark, tBuilder, cBuilder)
			        @inline(never) func __safeDI_t() -> T {
			            let reader = MarkReader(mark: mark.instance)
			            let __safeDI_apiBuilder_cBuilder = __safeDI_apiBuilder_t.cBuilder(mark.instance, reader)
			            @inline(never) func __safeDI_cBuilder() -> C {
			                let mark = Mark()
			                let __safeDI_apiBuilder_tBuilder = __safeDI_apiBuilder_cBuilder.tBuilder(mark)
			                @inline(never) func __safeDI_tBuilder() -> T {
			                    let reader = MarkReader(mark: mark)
			                    let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                    let api: any Api = __safeDI_apiBuilder_tBuilder.api(mark, reader, cBuilder)
			                    return T(reader: reader, cBuilder: cBuilder, api: api)
			                }
			                let tBuilder = Instantiator<T>(__safeDI_tBuilder)
			                return C(mark: mark, tBuilder: tBuilder)
			            }
			            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			            let api: any Api = __safeDI_apiBuilder_t.api(mark.instance, reader, cBuilder)
			            return T(reader: reader, cBuilder: cBuilder, api: api)
			        }
			        let t: T = __safeDI_t()
			        self.init(tBuilder: tBuilder, cBuilder: cBuilder, mark: mark, t: t)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_8FFA03E540887149 {}
			}
			"""),
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_apiBuilder_Hub() -> Hub.__safeDI_ApiCarrier<any Api> {
			            .init(tBuilder: { values_mark in __safeDI_apiBuilder_Hub_T_Scope() }, cBuilder: { values_mark, values_tBuilder in __safeDI_apiBuilder_Hub_C_Scope() }, t: { values_mark, values_tBuilder, values_cBuilder in __safeDI_apiBuilder_Hub_T_Scope() })
			        }
			        func __safeDI_apiBuilder_Hub_T_Scope() -> Hub.__safeDI_ApiCarrier_T<any Api> {
			            .init(
			                cBuilder: { values_mark, values_reader in __safeDI_apiBuilder_Hub_C_Scope() },
			                api: { scope_mark, scope_reader, scope_cBuilder in
			                    let mark = scope_mark
			                    let api: any Api = LiveApi(mark: mark)
			                    return api
			                }
			            )
			        }
			        func __safeDI_apiBuilder_Hub_C_Scope() -> Hub.__safeDI_ApiCarrier_C<any Api> {
			            .init(tBuilder: { values_mark in __safeDI_apiBuilder_Hub_T_Scope() })
			        }
			        func __safeDI_hub() -> Hub {
			            _ = Hub.__safeDI_Hub_8FFA03E540887149.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Hub(__safeDI_apiBuilder: __safeDI_apiBuilder_Hub())
			        }
			        let hub: Hub = __safeDI_hub()
			        self.init(hub: hub)
			    }
			}
			""",
		)
	}

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
		// `Hub`'s tree builds `A` with from a `@Sendable` closure: that function is `@Sendable`, so the place of `B`'s `api` is a
		// case of the `@Sendable` family, `a_Sendable`, and the plain root enum holds only `B`'s nested enum.
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
			expectedFeatureFile: (name: "Feature.swift", contents: """
			extension Hub {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_B<__safeDI_Built> {
			        public let api: (A) -> __safeDI_Built

			        public init(api: @escaping (A) -> __safeDI_Built) {
			            self.api = api
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiSendableCarrier<__safeDI_Built>: Sendable {
			        public let a_Sendable: __safeDI_ApiSendableCarrier_A<__safeDI_Built>

			        public init(a_Sendable: __safeDI_ApiSendableCarrier_A<__safeDI_Built>) {
			            self.a_Sendable = a_Sendable
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiSendableCarrier_A<__safeDI_Built>: Sendable {
			        public let bBuilder: @Sendable () -> __safeDI_ApiCarrier_B<__safeDI_Built>

			        public init(bBuilder: @escaping @Sendable () -> __safeDI_ApiCarrier_B<__safeDI_Built>) {
			            self.bBuilder = bBuilder
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_apiSendableBuilder: __safeDI_ApiSendableCarrier<any Api>) {
			        @inline(never) @Sendable nonisolated func __safeDI_a() -> A {
			            let __safeDI_apiSendableBuilder_a_Sendable = __safeDI_apiSendableBuilder.a_Sendable
			            let bBuilder = SendableInstantiator<B> {
			                __safeDI_bBuilder(__safeDI_apiSendableBuilder_a_Sendable: __safeDI_apiSendableBuilder_a_Sendable)
			            }
			            return A(bBuilder: bBuilder)
			        }
			        @inline(never) @Sendable nonisolated func __safeDI_bBuilder(__safeDI_apiSendableBuilder_a_Sendable: __safeDI_ApiSendableCarrier_A<any Api>) -> B {
			            let __safeDI_apiSendableBuilder_bBuilder = __safeDI_apiSendableBuilder_a_Sendable.bBuilder()
			            let a: A = __safeDI_a()
			            let api: any Api = __safeDI_apiSendableBuilder_bBuilder.api(a)
			            return B(api: api, a: a)
			        }
			        let a: A = __safeDI_a()
			        self.init(a: a)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_2987642971A9E8B1 {}
			}
			"""),
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        @Sendable nonisolated func __safeDI_apiSendableBuilder_Hub() -> Hub.__safeDI_ApiSendableCarrier<any Api> {
			            .init(a_Sendable: __safeDI_apiSendableBuilder_Hub_A_Scope())
			        }
			        @Sendable nonisolated func __safeDI_apiSendableBuilder_Hub_A_Scope() -> Hub.__safeDI_ApiSendableCarrier_A<any Api> {
			            .init(bBuilder: { __safeDI_apiBuilder_Hub_B_Scope() })
			        }
			        @Sendable nonisolated func __safeDI_apiBuilder_Hub_B_Scope() -> Hub.__safeDI_ApiCarrier_B<any Api> {
			            .init(api: { scope_a in
			                let api: any Api = LiveApi()
			                return api
			            })
			        }
			        func __safeDI_hub() -> Hub {
			            _ = Hub.__safeDI_Hub_2987642971A9E8B1.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Hub(__safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Hub())
			        }
			        let hub: Hub = __safeDI_hub()
			        self.init(hub: hub)
			    }
			}
			""",
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

	/// `Api`, `Mark`, `T`, `C` and `Hub`, a tangle of cycles no type always encloses: `Hub` builds `T` and `C` through
	/// instantiators, then declares `hub`'s declarations, `T` declares `t`'s declarations, then builds `C` before its hole
	/// `api`, and `C` instantiates `mark` before it builds `T`. `Mark` is a final class where `markIsFinalClass`, so a probe
	/// tells its instances apart.
	private static func tangle(t: [String], hub: [String] = [], markIsFinalClass: Bool = false) -> [String] {
		[
			"public protocol Api {}",
			seamFixtureType(named: "Mark", isFinalClass: markIsFinalClass, declarations: []),
			seamFixtureType(named: "T", declarations: t + ["@Instantiated public let cBuilder: Instantiator<C>", "@Instantiated public let api: any Api"]),
			seamFixtureType(named: "C", declarations: ["@Instantiated public let mark: Mark", "@Instantiated public let tBuilder: Instantiator<T>"]),
			seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let tBuilder: Instantiator<T>", "@Instantiated public let cBuilder: Instantiator<C>"] + hub),
		]
	}

	/// `Api`, `L`, `W`, `U`, `P`, `V` and `Hub`, two lazy cycles that share `U`: `Hub` instantiates `l` and `W`, `W` declares
	/// `w`'s declarations and builds `U` and `V`, which holds the hole `api`, `U` builds `P` and `W` again, and `P`
	/// instantiates its own `l` and builds `U` again.
	private static func typeBuiltAgainThroughSecondCycle(w: [String], instantiator: String = "Instantiator", conformances: String = "") -> [String] {
		[
			"public protocol Api\(conformances.isEmpty ? "" : ": Sendable") {}",
			seamFixtureType(named: "L", isFinalClass: true, declarations: [], conformances: conformances),
			seamFixtureType(named: "W", declarations: w + ["@Instantiated public let uBuilder: \(instantiator)<U>", "@Instantiated public let vBuilder: \(instantiator)<V>"], conformances: conformances),
			seamFixtureType(named: "U", declarations: ["@Instantiated public let pBuilder: \(instantiator)<P>", "@Instantiated public let wBuilder: \(instantiator)<W>"], conformances: conformances),
			seamFixtureType(named: "P", declarations: ["@Instantiated public let l: L", "@Instantiated public let uBuilder: \(instantiator)<U>"], conformances: conformances),
			seamFixtureType(named: "V", declarations: ["@Instantiated public let api: any Api"], conformances: conformances),
			seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let l: L", "@Instantiated public let wBuilder: \(instantiator)<W>"], conformances: conformances),
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

	private static func liveApi(_ declarations: [String], conformances: String = "") -> String {
		seamFixtureType(named: "LiveApi", declarations: declarations, conformances: ", Api" + conformances)
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

	/// `Feature`'s declarations where `Shell` builds `W`, which calls `Hub` and whose cycle declares `l` again: `P` directly,
	/// or `P` in a second cycle through `U`. `Hub` holds a place of `Api`, which `Feature` cannot fill.
	private static func shellCallingHubInsideCycle(throughSecondCycle: Bool) -> [String] {
		[
			"public protocol Api {}",
			seamFixtureType(named: "L", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let api: any Api"]),
			seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated public let wBuilder: Instantiator<W>"]),
		] + (throughSecondCycle ? [
			seamFixtureType(named: "W", declarations: ["@Instantiated public let hub: Hub", "@Instantiated public let uBuilder: Instantiator<U>"]),
			seamFixtureType(named: "U", declarations: ["@Instantiated public let pBuilder: Instantiator<P>", "@Instantiated public let wBuilder: Instantiator<W>"]),
			seamFixtureType(named: "P", declarations: ["@Instantiated public let l: L", "@Instantiated public let uBuilder: Instantiator<U>"]),
		] : [
			seamFixtureType(named: "W", declarations: ["@Instantiated public let hub: Hub", "@Instantiated public let pBuilder: Instantiator<P>"]),
			seamFixtureType(named: "P", declarations: ["@Instantiated public let l: L", "@Instantiated public let wBuilder: Instantiator<W>"]),
		])
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
	/// Where `expectedFeatureFile` or `expectedApp` is given, also expects `Feature`'s generated file of that name, or
	/// `App`'s `App.swift`, to be exactly it.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectValuesEqualInlineBuild(
		feature: [String],
		fulfiller: String,
		root: String,
		probe: DifferentialValueProbe,
		expectedFeatureFile: (name: String, contents: String)? = nil,
		expectedApp: String? = nil,
		expectedValues: String? = nil,
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let modules = Self.modules(feature: feature, app: [fulfiller, root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		if let expectedFeatureFile {
			#expect(output.modules["Feature"]?.generatedFiles[expectedFeatureFile.name] == generatedFileHeader + expectedFeatureFile.contents, sourceLocation: sourceLocation)
		}
		if let expectedApp {
			#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + expectedApp, sourceLocation: sourceLocation)
		}
		guard compileVerificationIsEnabled else { return }
		let inlineModules = Self.modules(feature: feature + [fulfiller], app: [root])
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: output, modules: modules),
			knownRight: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: inlineOutput, modules: inlineModules),
			probes: [probe],
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
		if let expectedValues {
			let description = try await DifferentialValueOracle.describe(SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: output, modules: modules), probes: [probe], filesToDelete: &filesToDelete)
			#expect(description == expectedValues, sourceLocation: sourceLocation)
		}
	}

	// MARK: Laps around a ring

	// Each test builds a ring a seam's place is on, walks several laps through every call that closes it, and pins which
	// declaration each read gets, beside the inline build's. Every lap reads the declaration nearest on its run-time route,
	// which the fold over (function, binding) that answers a place's re-entries assumes: a label a ring declares again is a
	// parameter of each member's function that reads it (`ScopeGenerator.cycleParameterSearch`, over the labels
	// `CycleClosingRedeclaredLabels` collects between a closed-on scope and its closing call), never a capture, and each
	// closing call passes the labels its own scope binds.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillReadsNearestMarkOnEveryLap_whenThreeRingMembersEachDeclareOneMarkAndReceiveTheOthers() async throws {
		let members = ["M0", "M1", "M2"]
		var feature = ["public protocol Api {}"]
		for member in members {
			let others = members.filter { $0 != member }
			feature.append(seamFixtureType(named: "Mark\(member)", isFinalClass: true, declarations: []))
			feature.append(seamFixtureType(named: member, declarations: ["@Instantiated public let mark\(member): Mark\(member)"] + others.map { "@Received public let mark\($0): Mark\($0)" } + others.map { "@Instantiated public let \($0.lowercased())Builder: Instantiator<\($0)>" } + ["@Instantiated public let api: any Api"]))
		}
		feature.append(seamFixtureType(named: "Hub", isSeam: true, declarations: members.map { "@Instantiated public let mark\($0): Mark\($0)" } + members.map { "@Instantiated public let \($0.lowercased())Builder: Instantiator<\($0)>" }))
		try await expectValuesEqualInlineBuild(
			feature: feature,
			fulfiller: Self.liveApi(members.map { "@Received public let mark\($0): Mark\($0)" }),
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let hub: Hub"]),
			probe: DifferentialValueProbe(name: "which member’s mark each lap’s api reads", expression: #"""
			{ () -> [String] in
			    let hub = Root().hub
			    var out = [String]()
			    func owner(_ mark: AnyObject, _ hubMark: AnyObject, _ path: [(String, AnyObject)]) -> String {
			        for (index, element) in path.enumerated().reversed() where element.1 === mark { return "\(element.0)@\(index)" }
			        return mark === hubMark ? "hub" : "other"
			    }
			    func report(_ api: any Api, _ path: [(String, AnyObject)]) {
			        let live = api as! LiveApi
			        out.append(path.map(\.0).joined(separator: ">") + ": " + owner(live.markM0, hub.markM0, path) + " " + owner(live.markM1, hub.markM1, path) + " " + owner(live.markM2, hub.markM2, path))
			    }
			    func visitM0(_ m: M0, _ path: [(String, AnyObject)]) {
			        let p = path + [("M0", m.markM0 as AnyObject)]
			        report(m.api, p)
			        guard p.count < 4 else { return }
			        visitM1(m.m1Builder.instantiate(), p)
			        visitM2(m.m2Builder.instantiate(), p)
			    }
			    func visitM1(_ m: M1, _ path: [(String, AnyObject)]) {
			        let p = path + [("M1", m.markM1 as AnyObject)]
			        report(m.api, p)
			        guard p.count < 4 else { return }
			        visitM0(m.m0Builder.instantiate(), p)
			        visitM2(m.m2Builder.instantiate(), p)
			    }
			    func visitM2(_ m: M2, _ path: [(String, AnyObject)]) {
			        let p = path + [("M2", m.markM2 as AnyObject)]
			        report(m.api, p)
			        guard p.count < 4 else { return }
			        visitM0(m.m0Builder.instantiate(), p)
			        visitM1(m.m1Builder.instantiate(), p)
			    }
			    visitM0(hub.m0Builder.instantiate(), [])
			    return out
			}()
			"""#),
			expectedValues: """
			probe which member’s mark each lap’s api reads
			Array<String>
			  0: String "M0: M0@0 hub hub"
			  1: String "M0>M1: M0@0 M1@1 hub"
			  2: String "M0>M1>M0: M0@2 M1@1 hub"
			  3: String "M0>M1>M0>M1: M0@2 M1@3 hub"
			  4: String "M0>M1>M0>M2: M0@2 M1@1 M2@3"
			  5: String "M0>M1>M2: M0@0 M1@1 M2@2"
			  6: String "M0>M1>M2>M0: M0@3 M1@1 M2@2"
			  7: String "M0>M1>M2>M1: M0@0 M1@3 M2@2"
			  8: String "M0>M2: M0@0 hub M2@1"
			  9: String "M0>M2>M0: M0@2 hub M2@1"
			  10: String "M0>M2>M0>M1: M0@2 M1@3 M2@1"
			  11: String "M0>M2>M0>M2: M0@2 hub M2@3"
			  12: String "M0>M2>M1: M0@0 M1@2 M2@1"
			  13: String "M0>M2>M1>M0: M0@3 M1@2 M2@1"
			  14: String "M0>M2>M1>M2: M0@0 M1@2 M2@3"

			""",
		)
	}

	@Test(arguments: [3, 4])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillFirstReadsRingsDeclarationOnLapAfterChainOfRenames_whenEachRingMemberRenamesTheLabelBeforeIt(renameCount: Int) async throws {
		// The ring is R<n> > … > R1 > D > R<n>, where R<i> receives l<i+1> renamed from l<i> and D declares l1; the fill
		// reads l<n+1>. Each lap moves the declaration one label along the chain, so the lap after `renameCount` laps is the
		// first to read D's l1: the number of laps the fold answers for grows with the chain.
		let renamers = (1...renameCount).reversed().map { "R\($0)" }
		var feature = ["public protocol Api {}", seamFixtureType(named: "L", isFinalClass: true, declarations: [])]
		feature.append(seamFixtureType(named: "Hub", isSeam: true, declarations: (1...renameCount).map { "@Instantiated public let l\($0): L" } + ["@Instantiated public let \(renamers[0].lowercased())Builder: Instantiator<\(renamers[0])>"]))
		for (index, renamer) in renamers.enumerated() {
			let label = renameCount - index
			let next = index + 1 < renamers.count ? renamers[index + 1] : "D"
			feature.append(seamFixtureType(named: renamer, declarations: ["@Received(fulfilledByDependencyNamed: \"l\(label)\", ofType: L.self) public let l\(label + 1): L"] + (index == 0 ? ["@Instantiated public let api: any Api"] : []) + ["@Instantiated public let \(next.lowercased())Builder: Instantiator<\(next)>"]))
		}
		feature.append(seamFixtureType(named: "D", declarations: ["@Instantiated public let l1: L", "@Instantiated public let \(renamers[0].lowercased())Builder: Instantiator<\(renamers[0])>"]))
		let first = renamers[0]
		let walkToD = renamers.dropFirst().map { "\($0.lowercased())Builder" } + ["dBuilder"]
		try await expectValuesEqualInlineBuild(
			feature: feature,
			fulfiller: Self.liveApi(["@Received public let l\(renameCount + 1): L"]),
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let hub: Hub"]),
			probe: DifferentialValueProbe(name: "whose l each lap’s api reads", expression: """
			{ () -> [String] in
			    let hub = Root().hub
			    var named: [(String, L)] = [\((1...renameCount).map { "(\"hub.l\($0)\", hub.l\($0))" }.joined(separator: ", "))]
			    var out = [String]()
			    var member = hub.\(first.lowercased())Builder.instantiate()
			    for lap in 1 ... \(renameCount + 2) {
			        let read = (member.api as! LiveApi).l\(renameCount + 1)
			        out.append("lap \\(lap): " + (named.first { $0.1 === read }?.0 ?? "other"))
			        let d = member\(walkToD.map { ".\($0).instantiate()" }.joined())
			        named.append(("D of lap \\(lap)", d.l1))
			        member = d.\(first.lowercased())Builder.instantiate()
			    }
			    return out
			}()
			"""),
			expectedValues: renameCount == 3 ? """
			probe whose l each lap’s api reads
			Array<String>
			  0: String "lap 1: hub.l3"
			  1: String "lap 2: hub.l2"
			  2: String "lap 3: hub.l1"
			  3: String "lap 4: D of lap 1"
			  4: String "lap 5: D of lap 2"

			""" : """
			probe whose l each lap’s api reads
			Array<String>
			  0: String "lap 1: hub.l4"
			  1: String "lap 2: hub.l3"
			  2: String "lap 3: hub.l2"
			  3: String "lap 4: hub.l1"
			  4: String "lap 5: D of lap 1"
			  5: String "lap 6: D of lap 2"

			""",
		)
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesLabelRingDeclaresAgainAsParameterOfReadersFunction_whenReaderIsBuiltInsideRingMembersBody(readerIsOnRing: Bool) async throws {
		// X reads `l`, which B, on the ring, declares again. Off the ring X is A's child; on it, X builds B. Either way X's
		// function takes `l` as a parameter, never a capture of the scope it is declared in, so each lap reads the `l` of
		// the lap before.
		try await expectValuesEqualInlineBuild(
			feature: [
				"public protocol Api {}",
				seamFixtureType(named: "L", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let l: L", "@Instantiated public let aBuilder: Instantiator<A>"]),
				seamFixtureType(named: "A", declarations: ["@Instantiated public let xBuilder: Instantiator<X>"] + (readerIsOnRing ? [] : ["@Instantiated public let bBuilder: Instantiator<B>"])),
				seamFixtureType(named: "X", declarations: ["@Received public let l: L", "@Instantiated public let api: any Api"] + (readerIsOnRing ? ["@Instantiated public let bBuilder: Instantiator<B>"] : [])),
				seamFixtureType(named: "B", declarations: ["@Instantiated public let l: L", "@Instantiated public let aBuilder: Instantiator<A>"]),
			],
			fulfiller: Self.liveApi(["@Received public let l: L"]),
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let hub: Hub"]),
			probe: DifferentialValueProbe(name: "whose l each lap’s X and its api read", expression: """
			{ () -> [String] in
			    let hub = Root().hub
			    var named: [(String, L)] = [("hub", hub.l)]
			    var out = [String]()
			    var a = hub.aBuilder.instantiate()
			    for lap in 1 ... 4 {
			        let x = a.xBuilder.instantiate()
			        func owner(_ l: L) -> String { named.first { $0.1 === l }?.0 ?? "other" }
			        out.append("lap \\(lap): \\(owner(x.l)) \\(owner((x.api as! LiveApi).l))")
			        let b = \(readerIsOnRing ? "x" : "a").bBuilder.instantiate()
			        named.append(("B of lap \\(lap)", b.l))
			        a = b.aBuilder.instantiate()
			    }
			    return out
			}()
			"""),
			expectedFeatureFile: ("Feature.swift", readerIsOnRing ? """
			extension Hub {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
			        public let aBuilder: (L) -> __safeDI_ApiCarrier_A<__safeDI_Built>

			        public init(aBuilder: @escaping (L) -> __safeDI_ApiCarrier_A<__safeDI_Built>) {
			            self.aBuilder = aBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(aBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_A<__safeDI_Built> {
			        public let xBuilder: (L) -> __safeDI_ApiCarrier_X<__safeDI_Built>

			        public init(xBuilder: @escaping (L) -> __safeDI_ApiCarrier_X<__safeDI_Built>) {
			            self.xBuilder = xBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(xBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_X<__safeDI_Built> {
			        public let api: (Instantiator<B>) -> __safeDI_Built

			        public init(api: @escaping (Instantiator<B>) -> __safeDI_Built) {
			            self.api = api
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(api: { _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
			        let l = L()
			        let __safeDI_apiBuilder_aBuilder = __safeDI_apiBuilder.aBuilder(l)
			        @inline(never) func __safeDI_aBuilder(l: L) -> A {
			            let __safeDI_apiBuilder_xBuilder = __safeDI_apiBuilder_aBuilder.xBuilder(l)
			            let xBuilder = Instantiator<X> {
			                __safeDI_xBuilder(l: l, __safeDI_apiBuilder_xBuilder: __safeDI_apiBuilder_xBuilder)
			            }
			            return A(xBuilder: xBuilder)
			        }
			        @inline(never) func __safeDI_xBuilder(l: L, __safeDI_apiBuilder_xBuilder: __safeDI_ApiCarrier_X<any Api>) -> X {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            let api: any Api = __safeDI_apiBuilder_xBuilder.api(bBuilder)
			            return X(l: l, api: api, bBuilder: bBuilder)
			        }
			        @inline(never) func __safeDI_bBuilder() -> B {
			            let l = L()
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(l: l)
			            }
			            return B(l: l, aBuilder: aBuilder)
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(l: l)
			        }
			        self.init(l: l, aBuilder: aBuilder)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_A81E82AF600D9E71 {}
			}
			""" : """
			extension Hub {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
			        public let aBuilder: (L) -> __safeDI_ApiCarrier_A<__safeDI_Built>

			        public init(aBuilder: @escaping (L) -> __safeDI_ApiCarrier_A<__safeDI_Built>) {
			            self.aBuilder = aBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(aBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_A<__safeDI_Built> {
			        public let xBuilder: (L, Instantiator<B>) -> __safeDI_ApiCarrier_X<__safeDI_Built>

			        public init(xBuilder: @escaping (L, Instantiator<B>) -> __safeDI_ApiCarrier_X<__safeDI_Built>) {
			            self.xBuilder = xBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(xBuilder: { _, _ in .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_X<__safeDI_Built> {
			        public let api: () -> __safeDI_Built

			        public init(api: @escaping () -> __safeDI_Built) {
			            self.api = api
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(api: { __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
			        let l = L()
			        let __safeDI_apiBuilder_aBuilder = __safeDI_apiBuilder.aBuilder(l)
			        @inline(never) func __safeDI_aBuilder(l: L) -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            let __safeDI_apiBuilder_xBuilder = __safeDI_apiBuilder_aBuilder.xBuilder(l, bBuilder)
			            let xBuilder = Instantiator<X> {
			                __safeDI_xBuilder(l: l, __safeDI_apiBuilder_xBuilder: __safeDI_apiBuilder_xBuilder)
			            }
			            return A(xBuilder: xBuilder, bBuilder: bBuilder)
			        }
			        @inline(never) func __safeDI_bBuilder() -> B {
			            let l = L()
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(l: l)
			            }
			            return B(l: l, aBuilder: aBuilder)
			        }
			        @inline(never) func __safeDI_xBuilder(l: L, __safeDI_apiBuilder_xBuilder: __safeDI_ApiCarrier_X<any Api>) -> X {
			            let api: any Api = __safeDI_apiBuilder_xBuilder.api()
			            return X(l: l, api: api)
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(l: l)
			        }
			        self.init(l: l, aBuilder: aBuilder)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_B1DF1D25EC5280B1 {}
			}
			"""),
			expectedValues: """
			probe whose l each lap’s X and its api read
			Array<String>
			  0: String "lap 1: hub hub"
			  1: String "lap 2: B of lap 1 B of lap 1"
			  2: String "lap 3: B of lap 2 B of lap 2"
			  3: String "lap 4: B of lap 3 B of lap 3"

			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_closingCallPassesItsOwnSidesDeclaration_whenRingMemberIsBuiltBeneathValueAndBeneathLazilyInstantiatedWrapper() async throws {
		// Leaf receives `theme` only if available; First declares it as a value, Second as a `LazilyInstantiated`, and Mid,
		// between each Leaf and its closing call, declares it again as a wrapper. Each side's Leaf has a function of its own,
		// and each closing call hands it the `theme` of its own Mid.
		try await expectValuesEqualInlineBuild(
			feature: [
				"public protocol Api {}",
				seamFixtureType(named: "Theme", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let first: First", "@Instantiated public let second: Second"]),
				seamFixtureType(named: "First", declarations: ["@Instantiated public let theme: Theme", "@Instantiated public let leafBuilder: Instantiator<Leaf>"]),
				seamFixtureType(named: "Second", declarations: ["@Instantiated public let theme: LazilyInstantiated<Theme>", "@Instantiated public let leafBuilder: Instantiator<Leaf>"]),
				seamFixtureType(named: "Leaf", declarations: ["@Received(onlyIfAvailable: true) public let theme: Theme?", "@Instantiated public let midBuilder: Instantiator<Mid>", "@Instantiated public let api: any Api"]),
				seamFixtureType(named: "Mid", declarations: ["@Instantiated public let theme: LazilyInstantiated<Theme>", "@Instantiated public let leafBuilder: Instantiator<Leaf>"]),
			],
			fulfiller: Self.liveApi(["@Received(onlyIfAvailable: true) public let theme: Theme?"]),
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let hub: Hub"]),
			probe: DifferentialValueProbe(name: "whose theme each lap’s Leaf and its api read", expression: """
			{ () -> [String] in
			    let hub = Root().hub
			    var out = [String]()
			    for (side, start, sideTheme) in [("First", hub.first.leafBuilder, hub.first.theme), ("Second", hub.second.leafBuilder, hub.second.theme.instance)] {
			        var named: [(String, Theme)] = [(side, sideTheme)]
			        var leaf = start.instantiate()
			        for lap in 1 ... 3 {
			            func owner(_ theme: Theme?) -> String { theme.map { theme in named.last { $0.1 === theme }?.0 ?? "other" } ?? "nil" }
			            out.append("\\(side) lap \\(lap): \\(owner(leaf.theme)) \\(owner((leaf.api as! LiveApi).theme))")
			            let mid = leaf.midBuilder.instantiate()
			            named.append(("Mid of lap \\(lap)", mid.theme.instance))
			            leaf = mid.leafBuilder.instantiate()
			        }
			    }
			    return out
			}()
			"""),
			expectedValues: """
			probe whose theme each lap’s Leaf and its api read
			Array<String>
			  0: String "First lap 1: First First"
			  1: String "First lap 2: Mid of lap 1 Mid of lap 1"
			  2: String "First lap 3: Mid of lap 2 Mid of lap 2"
			  3: String "Second lap 1: Second Second"
			  4: String "Second lap 2: Mid of lap 1 Mid of lap 1"
			  5: String "Second lap 3: Mid of lap 2 Mid of lap 2"

			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillReadsBothLabelsFromOneDeclarer_whenTwoWaysRoundRingEachDeclareBothLabels() async throws {
		// R receives l1 and l2, and A and B, the two ways round the ring, each declare both: on every route the fill reads
		// both of the nearest declarer, never one label of one way and the other of the other.
		try await expectValuesEqualInlineBuild(
			feature: [
				"public protocol Api {}",
				seamFixtureType(named: "L", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let l1: L", "@Instantiated public let l2: L", "@Instantiated public let rBuilder: Instantiator<R>"]),
				seamFixtureType(named: "R", declarations: ["@Received public let l1: L", "@Received public let l2: L", "@Instantiated public let aBuilder: Instantiator<A>", "@Instantiated public let bBuilder: Instantiator<B>", "@Instantiated public let api: any Api"]),
				seamFixtureType(named: "A", declarations: ["@Instantiated public let l1: L", "@Instantiated public let l2: L", "@Instantiated public let rBuilder: Instantiator<R>"]),
				seamFixtureType(named: "B", declarations: ["@Instantiated public let l1: L", "@Instantiated public let l2: L", "@Instantiated public let rBuilder: Instantiator<R>"]),
			],
			fulfiller: Self.liveApi(["@Received public let l1: L", "@Received public let l2: L"]),
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let hub: Hub"]),
			probe: DifferentialValueProbe(name: "whose l1 and l2 each route’s api reads", expression: """
			{ () -> [String] in
			    let hub = Root().hub
			    var out = [String]()
			    func visit(_ r: R, _ path: String, _ named: [(String, L, L)]) {
			        let live = r.api as! LiveApi
			        out.append("\\(path): \\(named.last { $0.1 === live.l1 }?.0 ?? "other") \\(named.last { $0.2 === live.l2 }?.0 ?? "other")")
			        guard named.count < 4 else { return }
			        let a = r.aBuilder.instantiate()
			        visit(a.rBuilder.instantiate(), path + ">A>R", named + [("A of lap \\(named.count)", a.l1, a.l2)])
			        let b = r.bBuilder.instantiate()
			        visit(b.rBuilder.instantiate(), path + ">B>R", named + [("B of lap \\(named.count)", b.l1, b.l2)])
			    }
			    visit(hub.rBuilder.instantiate(), "R", [("hub", hub.l1, hub.l2)])
			    return out
			}()
			"""),
			expectedValues: """
			probe whose l1 and l2 each route’s api reads
			Array<String>
			  0: String "R: hub hub"
			  1: String "R>A>R: A of lap 1 A of lap 1"
			  2: String "R>A>R>A>R: A of lap 2 A of lap 2"
			  3: String "R>A>R>A>R>A>R: A of lap 3 A of lap 3"
			  4: String "R>A>R>A>R>B>R: B of lap 3 B of lap 3"
			  5: String "R>A>R>B>R: B of lap 2 B of lap 2"
			  6: String "R>A>R>B>R>A>R: A of lap 3 A of lap 3"
			  7: String "R>A>R>B>R>B>R: B of lap 3 B of lap 3"
			  8: String "R>B>R: B of lap 1 B of lap 1"
			  9: String "R>B>R>A>R: A of lap 2 A of lap 2"
			  10: String "R>B>R>A>R>A>R: A of lap 3 A of lap 3"
			  11: String "R>B>R>A>R>B>R: B of lap 3 B of lap 3"
			  12: String "R>B>R>B>R: B of lap 2 B of lap 2"
			  13: String "R>B>R>B>R>A>R: A of lap 3 A of lap 3"
			  14: String "R>B>R>B>R>B>R: B of lap 3 B of lap 3"

			""",
		)
	}

	private var filesToDelete: [URL]
}
