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

/// A caller generates one function per case of a seam's enums, and builds a fill for a case's other places only to judge
/// each. It builds one such fill for the places of a case that hand their fills the same values, and judges the others
/// against it, each with its own place (`ScopeGenerator.FillStoodFor`).
struct SafeDIToolSeamFillSharedBetweenPlacesTests: ~Copyable {
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
	mutating func generate_buildsFillsGrowingWithTheCasesNotThePaths_whenSeamReachesItsPlacesAlongManyPaths() async {
		// Shape E (`SafeDIToolSeamScopeByTypeTests.shapeEModules`) triples the paths to its places, those of the last layer's
		// four screens, with each layer of screens: 36, 108 and 324 paths to four cases. The caller builds two fills per case,
		// the one that generates code and one that stands for every other place, whatever the paths.
		for (screenCount, pathCount) in [(12, 36), (16, 108), (20, 324)] {
			let (fills, error) = await fillsOfCalls { filesToDelete in
				_ = try await executeSafeDIToolMultiModuleTest(
					modules: SafeDIToolSeamScopeByTypeTests.shapeEModules(screenCount: screenCount),
					integration: .moduleInfo,
					compileVerification: .skipped,
					filesToDelete: &filesToDelete,
				)
			}
			#expect(error == nil)
			#expect(fills.last.map { [$0.builtFillCount, $0.placeStoodForCount] } == [8, pathCount - 8])
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFindingOfEveryPlaceOnce_whenAnotherPlacesFillStandsForPlaceWithFinding() async {
		// `Home` builds `Panel` beneath `First`, `Second` and `Third`, so `Panel`'s `api` is three places of one case, each
		// handed the same values, as is `Row`'s. `LiveApi` receives `rowBuilder`, which `Panel` builds after `api` and is
		// building at `Row`'s `api`, at every one of them.
		let (fills, error) = await fillsOfCalls { filesToDelete in
			_ = try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					parentDeclarations: [["@Instantiated let panel: Panel"], ["@Instantiated let panel: Panel"], ["@Instantiated let panel: Panel"]],
					panelDeclarations: ["@Instantiated let api: any Api", "@Instantiated let rowBuilder: Instantiator<Row>"],
					liveApiDeclarations: ["@Received(onlyIfAvailable: true) let rowBuilder: Instantiator<Row>?"],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `rowBuilder: Instantiator<Row>?`, which `Panel` builds only after `Home`’s tree calls the builder for `Panel`’s `api: any Api` (`api` of `apiBuilder`), so SafeDI does not hand it to that builder. Instantiate `rowBuilder` on a type above `Home`, and receive it on `Panel` in place of its @Instantiated declaration, so that the caller’s tree builds it, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Panel.swift"]):9:5: note: `Panel` declares `rowBuilder: Instantiator<Row>` here.
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `rowBuilder: Instantiator<Row>?`, which `Home`’s tree is building where it calls the builder for `Row`’s `api: any Api` (`api` of `apiBuilder`). Inline, `LiveApi` can get an instantiator of its own, made from the function `Home`’s initializer declares for `rowBuilder`, which code generated outside module `Feature` cannot refer to. Instantiate `rowBuilder` on a type above `Home`, and receive it on `Panel` in place of its @Instantiated declaration, so that the caller’s tree builds it, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Panel.swift"]):9:5: note: `Panel` instantiates `rowBuilder: Instantiator<Row>` here.
			"""
		}) {
			if let error {
				throw error
			}
		}
		// Of each case's three places, the first is judged with the fill that generates code, the second with a fill of its
		// own, and the third against the second's.
		#expect(fills.last.map { [$0.builtFillCount, $0.placeStoodForCount] } == [4, 2])
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsCaptureOfEveryPlacesDeclaration_whenAnotherPlacesFillStandsForPlaceWhoseFillCapturesWrapper(buildsFillOfEveryPlace: Bool) async {
		// `First`, `Second` and `Third` each build `rowBuilder` and then `Panel`, so `Panel`'s `api` is three places of one
		// case whose fields are equal but declared by three types. `LiveApi` builds `Worker` in a `@Sendable` function, and
		// `Worker` receives `rowBuilder`, which that function cannot capture, at every one of the three.
		let (fills, error) = await fillsOfCalls { filesToDelete in
			_ = try await SeamFillSharing.$buildsFillOfEveryPlace.withValue(buildsFillOfEveryPlace) {
				try await executeSafeDIToolMultiModuleTest(
					modules: Self.modules(
						parentDeclarations: Array(repeating: ["@Instantiated let rowBuilder: Instantiator<Row>", "@Instantiated let panel: Panel"], count: 3),
						panelDeclarations: ["@Instantiated let api: any Api"],
						liveApiDeclarations: ["@Instantiated let workerBuilder: SendableInstantiator<Worker>"],
						appDeclarations: [seamFixtureType(named: "Worker", declarations: ["@Received let rowBuilder: Instantiator<Row>"])],
						rowDeclarations: [],
					),
					integration: .moduleInfo,
					filesToDelete: &filesToDelete,
				)
			}
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Worker.swift"]):9:5: error: @Received property `rowBuilder: Instantiator<Row>` cannot be received inside a `@Sendable` function in chain: Root -> Home -> LiveApi -> Worker. SafeDI builds `workerBuilder: SendableInstantiator<Worker>` on `LiveApi` in a `@Sendable` function, which cannot capture `rowBuilder: Instantiator<Row>` on `First`, because `Instantiator<Row>` is not `Sendable`. Declare `rowBuilder` on `First`, `Second`, and `Third`, and this property, as `SendableInstantiator<Row>` to fix. `SendableInstantiator<Row>` builds `Row` in a `@Sendable` function, so what the tree of `Row` receives from outside that function must be `Sendable` too.
			\(fixtures["Feature"]!["First.swift"]):8:5: note: `rowBuilder: Instantiator<Row>` is declared here
			\(fixtures["App"]!["Worker.swift"]):9:5: error: @Received property `rowBuilder: Instantiator<Row>` cannot be received inside a `@Sendable` function in chain: Root -> Home -> LiveApi -> Worker. SafeDI builds `workerBuilder: SendableInstantiator<Worker>` on `LiveApi` in a `@Sendable` function, which cannot capture `rowBuilder: Instantiator<Row>` on `Second`, because `Instantiator<Row>` is not `Sendable`. Declare `rowBuilder` on `First`, `Second`, and `Third`, and this property, as `SendableInstantiator<Row>` to fix. `SendableInstantiator<Row>` builds `Row` in a `@Sendable` function, so what the tree of `Row` receives from outside that function must be `Sendable` too.
			\(fixtures["Feature"]!["Second.swift"]):8:5: note: `rowBuilder: Instantiator<Row>` is declared here
			\(fixtures["App"]!["Worker.swift"]):9:5: error: @Received property `rowBuilder: Instantiator<Row>` cannot be received inside a `@Sendable` function in chain: Root -> Home -> LiveApi -> Worker. SafeDI builds `workerBuilder: SendableInstantiator<Worker>` on `LiveApi` in a `@Sendable` function, which cannot capture `rowBuilder: Instantiator<Row>` on `Third`, because `Instantiator<Row>` is not `Sendable`. Declare `rowBuilder` on `First`, `Second`, and `Third`, and this property, as `SendableInstantiator<Row>` to fix. `SendableInstantiator<Row>` builds `Row` in a `@Sendable` function, so what the tree of `Row` receives from outside that function must be `Sendable` too.
			\(fixtures["Feature"]!["Third.swift"]):8:5: note: `rowBuilder: Instantiator<Row>` is declared here
			"""
		}) {
			if let error {
				throw error
			}
		}
		// The third place is judged against the second's fill unless every place gets its own.
		#expect(fills.last.map { [$0.builtFillCount, $0.placeStoodForCount] } == (buildsFillOfEveryPlace ? [3, 0] : [2, 1]))
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesDeclarationClosedOn_whenAnotherPlacesFillStandsForPlaceThatReachesItAtAnotherDepth(buildsFillOfEveryPlace: Bool) async {
		// `Shell` builds `Panel` beneath `A` and `B`, and one level deeper beneath `C`'s `Mid`, so `Panel`'s `api` is three
		// places of one case, the third of which has `shellBuilder` one declaration farther up its path. `LiveApi` builds
		// `shellBuilder` again, which closes a cycle on `Home`'s at every one of them.
		let (fills, error) = await fillsOfCalls { filesToDelete in
			_ = try await SeamFillSharing.$buildsFillOfEveryPlace.withValue(buildsFillOfEveryPlace) {
				try await executeSafeDIToolMultiModuleTest(
					modules: SafeDIToolSeamBuilderParameterTests.modules(
						feature: [
							"public protocol Api {}",
							seamFixtureType(named: "Panel", declarations: ["@Instantiated let api: any Api"]),
							seamFixtureType(named: "A", declarations: ["@Instantiated let panel: Panel"]),
							seamFixtureType(named: "B", declarations: ["@Instantiated let panel: Panel"]),
							seamFixtureType(named: "Mid", declarations: ["@Instantiated let panel: Panel"]),
							seamFixtureType(named: "C", declarations: ["@Instantiated let mid: Mid"]),
							seamFixtureType(named: "Shell", declarations: ["@Instantiated let a: A", "@Instantiated let b: B", "@Instantiated let c: C"]),
							seamFixtureType(named: "Home", isSeam: true, declarations: ["@Instantiated let shellBuilder: Instantiator<Shell>"]),
						],
						app: [
							SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Instantiated let shellBuilder: Instantiator<Shell>"]),
							seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let home: Home"]),
						],
					),
					integration: .moduleInfo,
					filesToDelete: &filesToDelete,
				)
			}
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: SafeDI cannot fill the builder for `Panel`’s `api: any Api` (`api` of `apiBuilder`) in `Home`’s dependency tree: `LiveApi`, which fills it, instantiates `shellBuilder: Instantiator<Shell>`, which `Home`’s tree is building where it builds `api` (Home -> shellBuilder -> Shell -> a -> A -> panel -> Panel -> api -> LiveApi -> shellBuilder). Code generated outside module `Feature` cannot refer to the function `Home`’s initializer builds `Shell` with, and building it again would hand it other values than `Home`’s tree holds. Instantiate `Home` where `LiveApi` builds `Shell` (`@Instantiated let homeBuilder: Instantiator<Home>`), so the cycle re-enters through the initializer SafeDI generates for `Home`, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Home.swift"]):7:5: note: `Home` instantiates `shellBuilder: Instantiator<Shell>` here.
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: SafeDI cannot fill the builder for `Panel`’s `api: any Api` (`api` of `apiBuilder`) in `Home`’s dependency tree: `LiveApi`, which fills it, instantiates `shellBuilder: Instantiator<Shell>`, which `Home`’s tree is building where it builds `api` (Home -> shellBuilder -> Shell -> b -> B -> panel -> Panel -> api -> LiveApi -> shellBuilder). Code generated outside module `Feature` cannot refer to the function `Home`’s initializer builds `Shell` with, and building it again would hand it other values than `Home`’s tree holds. Instantiate `Home` where `LiveApi` builds `Shell` (`@Instantiated let homeBuilder: Instantiator<Home>`), so the cycle re-enters through the initializer SafeDI generates for `Home`, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Home.swift"]):7:5: note: `Home` instantiates `shellBuilder: Instantiator<Shell>` here.
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: SafeDI cannot fill the builder for `Panel`’s `api: any Api` (`api` of `apiBuilder`) in `Home`’s dependency tree: `LiveApi`, which fills it, instantiates `shellBuilder: Instantiator<Shell>`, which `Home`’s tree is building where it builds `api` (Home -> shellBuilder -> Shell -> c -> C -> mid -> Mid -> panel -> Panel -> api -> LiveApi -> shellBuilder). Code generated outside module `Feature` cannot refer to the function `Home`’s initializer builds `Shell` with, and building it again would hand it other values than `Home`’s tree holds. Instantiate `Home` where `LiveApi` builds `Shell` (`@Instantiated let homeBuilder: Instantiator<Home>`), so the cycle re-enters through the initializer SafeDI generates for `Home`, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Home.swift"]):7:5: note: `Home` instantiates `shellBuilder: Instantiator<Shell>` here.
			"""
		}) {
			if let error {
				throw error
			}
		}
		#expect(fills.last.map { [$0.builtFillCount, $0.placeStoodForCount] } == (buildsFillOfEveryPlace ? [3, 0] : [2, 1]))
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsFillOfItsOwnForPlace_whenOnlyItsPathHoldsDeclarationItsFillClosesCycleOn(buildsFillOfEveryPlace: Bool) async {
		// `Panel`'s `api` is three places of one case, beneath `A`, `B` and `Shell`, and only the third has `shellBuilder`
		// on its path. `LiveApi` builds `shellBuilder` again: beneath `A` and `B` that builds another `Shell`, whose
		// `panel` no declaration of the place's path is, and beneath `Shell` it closes a cycle on `Home`'s own. `B`'s
		// fill does not stand for `Shell`'s place, whose error it would not find.
		let (fills, error) = await fillsOfCalls { filesToDelete in
			_ = try await SeamFillSharing.$buildsFillOfEveryPlace.withValue(buildsFillOfEveryPlace) {
				try await executeSafeDIToolMultiModuleTest(
					modules: SafeDIToolSeamBuilderParameterTests.modules(
						feature: [
							"public protocol Api {}",
							seamFixtureType(named: "Panel", declarations: ["@Instantiated let api: any Api"]),
							seamFixtureType(named: "A", declarations: ["@Instantiated let aPanel: Panel"]),
							seamFixtureType(named: "B", declarations: ["@Instantiated let bPanel: Panel"]),
							seamFixtureType(named: "Shell", declarations: ["@Instantiated let panel: Panel"]),
							seamFixtureType(named: "Home", isSeam: true, declarations: ["@Instantiated let a: A", "@Instantiated let b: B", "@Instantiated let shellBuilder: Instantiator<Shell>"]),
						],
						app: [
							SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Instantiated let shellBuilder: Instantiator<Shell>"]),
							seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let home: Home"]),
						],
					),
					integration: .moduleInfo,
					filesToDelete: &filesToDelete,
				)
			}
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: SafeDI cannot fill the builder for `Panel`’s `api: any Api` (`api` of `apiBuilder`) in `Home`’s dependency tree: `LiveApi`, which fills it, instantiates `shellBuilder: Instantiator<Shell>`, which `Home`’s tree is building where it builds `api` (Home -> shellBuilder -> Shell -> panel -> Panel -> api -> LiveApi -> shellBuilder). Code generated outside module `Feature` cannot refer to the function `Home`’s initializer builds `Shell` with, and building it again would hand it other values than `Home`’s tree holds. Instantiate `Home` where `LiveApi` builds `Shell` (`@Instantiated let homeBuilder: Instantiator<Home>`), so the cycle re-enters through the initializer SafeDI generates for `Home`, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Home.swift"]):11:5: note: `Home` instantiates `shellBuilder: Instantiator<Shell>` here.
			"""
		}) {
			if let error {
				throw error
			}
		}
		#expect(fills.last.map { [$0.builtFillCount, $0.placeStoodForCount] } == [3, 0])
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsFillOfItsOwnForPlace_whenItHandsItsFillOptionalOfValueOtherPlacesHand(buildsFillOfEveryPlace: Bool) async {
		// `First` and `Second` hand their fills a `token` of `Token`, and `Third`, built behind an instantiator, the
		// `Token?` it forwards, which `LiveApi` receives only if available: the fields differ in their type alone.
		let (fills, error) = await fillsOfCalls { filesToDelete in
			_ = try await SeamFillSharing.$buildsFillOfEveryPlace.withValue(buildsFillOfEveryPlace) {
				try await executeSafeDIToolMultiModuleTest(
					modules: SafeDIToolSeamBuilderParameterTests.modules(
						feature: [
							"public protocol Api {}",
							seamFixtureType(named: "Panel", declarations: ["@Instantiated let api: any Api"]),
							seamFixtureType(named: "Token", declarations: []),
							seamFixtureType(named: "First", declarations: ["@Instantiated let token: Token", "@Instantiated let panel: Panel"]),
							seamFixtureType(named: "Second", declarations: ["@Instantiated let token: Token", "@Instantiated let panel: Panel"]),
							seamFixtureType(named: "Third", declarations: ["@Forwarded let token: Token?", "@Instantiated let panel: Panel"]),
							seamFixtureType(named: "Home", isSeam: true, declarations: ["@Instantiated let first: First", "@Instantiated let second: Second", "@Instantiated let thirdBuilder: Instantiator<Third>"]),
						],
						app: [
							SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received(onlyIfAvailable: true) let token: Token?"]),
							seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let home: Home"]),
						],
					),
					integration: .moduleInfo,
					filesToDelete: &filesToDelete,
				)
			}
		}
		#expect(error == nil)
		#expect(fills.last.map { [$0.builtFillCount, $0.placeStoodForCount] } == [3, 0])
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsFillOfItsOwnForPlace_whenItHandsItsFillValueOtherPlacesHandDeferred(buildsFillOfEveryPlace: Bool) async {
		// `Home` receives `token` for `Detail`, built behind an instantiator, so its parameter is deferred, and `First`'s and
		// `Second`'s places hand their fills the deferred parameter. `Third` builds a `token` of its own, by value.
		let (fills, error) = await fillsOfCalls { filesToDelete in
			_ = try await SeamFillSharing.$buildsFillOfEveryPlace.withValue(buildsFillOfEveryPlace) {
				try await executeSafeDIToolMultiModuleTest(
					modules: SafeDIToolSeamBuilderParameterTests.modules(
						feature: [
							"public protocol Api {}",
							seamFixtureType(named: "Panel", declarations: ["@Instantiated let api: any Api"]),
							seamFixtureType(named: "Token", declarations: []),
							seamFixtureType(named: "Detail", declarations: ["@Received let token: Token"]),
							seamFixtureType(named: "First", declarations: ["@Instantiated let panel: Panel"]),
							seamFixtureType(named: "Second", declarations: ["@Instantiated let panel: Panel"]),
							seamFixtureType(named: "Third", declarations: ["@Instantiated let token: Token", "@Instantiated let panel: Panel"]),
							seamFixtureType(named: "Home", isSeam: true, declarations: ["@Instantiated let detailBuilder: Instantiator<Detail>", "@Instantiated let first: First", "@Instantiated let second: Second", "@Instantiated let third: Third"]),
						],
						app: [
							SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received let token: Token"]),
							seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let token: Token", "@Instantiated let home: Home"]),
						],
					),
					integration: .moduleInfo,
					filesToDelete: &filesToDelete,
				)
			}
		}
		#expect(error == nil)
		#expect(fills.last.map { [$0.builtFillCount, $0.placeStoodForCount] } == [3, 0])
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsFillOfItsOwnForPlace_whenOnlyItsBuilderIsSendable(buildsFillOfEveryPlace: Bool) async {
		// `Third` builds `Panel` behind a `SendableInstantiator`, so only its place's builder is `@Sendable`.
		let (fills, error) = await fillsOfCalls { filesToDelete in
			_ = try await SeamFillSharing.$buildsFillOfEveryPlace.withValue(buildsFillOfEveryPlace) {
				try await executeSafeDIToolMultiModuleTest(
					modules: SafeDIToolSeamBuilderParameterTests.modules(
						feature: [
							"public protocol Api: Sendable {}",
							seamFixtureType(named: "Panel", declarations: ["@Instantiated let api: any Api"]).replacingOccurrences(of: ": Instantiable", with: ": Instantiable, Sendable"),
							seamFixtureType(named: "First", declarations: ["@Instantiated let panel: Panel"]),
							seamFixtureType(named: "Second", declarations: ["@Instantiated let panel: Panel"]),
							seamFixtureType(named: "Third", declarations: ["@Instantiated let panelBuilder: SendableInstantiator<Panel>"]),
							seamFixtureType(named: "Home", isSeam: true, declarations: ["@Instantiated let first: First", "@Instantiated let second: Second", "@Instantiated let third: Third"]),
						],
						app: [
							SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: []).replacingOccurrences(of: ": Instantiable", with: ": Instantiable, Sendable"),
							seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let home: Home"]),
						],
					),
					integration: .moduleInfo,
					filesToDelete: &filesToDelete,
				)
			}
		}
		#expect(error == nil)
		#expect(fills.last.map { [$0.builtFillCount, $0.placeStoodForCount] } == [3, 0])
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFindingOfOnePlace_whenAnotherPlacesFillStandsForPlaceThatBindsValueAfterIt(buildsFillOfEveryPlace: Bool) async {
		// Only `Third` declares `token`, which receives `panel` and so is built after it: no place hands its fill a `token`, so
		// the three places' fills are alike and `Second`'s stands for `Third`'s, whose own record alone says that the value
		// `LiveApi` reads is bound after it.
		let (fills, error) = await fillsOfCalls { filesToDelete in
			_ = try await SeamFillSharing.$buildsFillOfEveryPlace.withValue(buildsFillOfEveryPlace) {
				try await executeSafeDIToolMultiModuleTest(
					modules: Self.modules(
						parentDeclarations: [
							["@Instantiated let panel: Panel"],
							["@Instantiated let panel: Panel"],
							["@Instantiated let panel: Panel", "@Instantiated let token: Token"],
						],
						panelDeclarations: ["@Instantiated let api: any Api"],
						liveApiDeclarations: ["@Received(onlyIfAvailable: true) let token: Token?"],
						tokenDeclarations: ["@Received let panel: Panel"],
					),
					integration: .moduleInfo,
					filesToDelete: &filesToDelete,
				)
			}
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `token: Token?`, which `Third` builds only after `Home`’s tree calls the builder for `Panel`’s `api: any Api` (`api` of `apiBuilder`), so SafeDI does not hand it to that builder. Declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Third.swift"]):9:5: note: `Third` declares `token: Token` here.
			"""
		}) {
			if let error {
				throw error
			}
		}
		#expect(fills.last.map { [$0.builtFillCount, $0.placeStoodForCount] } == (buildsFillOfEveryPlace ? [3, 0] : [2, 1]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsFillOfItsOwnForPlace_whenPlacesOfOneCaseHandTheirFillsOtherValues() async {
		// `First`, `Third` and `Fourth` build `token` before `panel`, and `Second` builds none, so the place beneath `Second`
		// hands its fill no `token`, which `LiveApi` then reads from `Root`: that place is judged with a fill of its own,
		// `Third`'s with another, and `Fourth`'s against `Third`'s.
		let (fills, error) = await fillsOfCalls { filesToDelete in
			_ = try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					parentDeclarations: [
						["@Instantiated let token: Token", "@Instantiated let panel: Panel"],
						["@Instantiated let panel: Panel"],
						["@Instantiated let token: Token", "@Instantiated let panel: Panel"],
						["@Instantiated let token: Token", "@Instantiated let panel: Panel"],
					],
					panelDeclarations: ["@Instantiated let api: any Api"],
					liveApiDeclarations: ["@Received let token: Token"],
					rootDeclarations: ["@Instantiated let token: Token"],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(error == nil)
		#expect(fills.last.map { [$0.builtFillCount, $0.placeStoodForCount] } == [3, 1])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_unfoldsFillEdgesOfACall_whenItsFirstPlaceIsBeneathAFillOfItsOwnHole() async throws {
		// `LiveGadget`'s `homeBuilder` is first drawn beneath the fill of `Home`'s `gadget`, where it passes that fill on and
		// draws no edge, and then beneath the fill of `Office`'s, where it fills `gadget` itself: the declaration's column is
		// the second, so the unfolded DOT graph draws the fill edge where the tree does. `Home`'s `lamp`, which is no hole,
		// is drawn in neither: a graph draws only the holes of a seam it calls, whose own children its module's graph draws.
		// The fill of `Home`'s `gadget` beneath that `homeBuilder` draws its own `homeBuilder`, where the fill above it is of
		// `Office`'s hole, another call's, which closes no cycle on it.
		let modules = SafeDIToolSeamBuilderParameterTests.modules(
			feature: [
				"public protocol Gadget {}",
				seamFixtureType(named: "Lamp", declarations: []),
				seamFixtureType(named: "Home", isSeam: true, declarations: ["@Instantiated let lamp: Lamp", "@Instantiated let gadget: any Gadget"]),
				seamFixtureType(named: "Office", isSeam: true, declarations: ["@Instantiated let gadget: any Gadget"]),
			],
			app: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Instantiated let homeBuilder: Instantiator<Home>"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let home: Home", "@Instantiated let office: Office"]),
			],
		)
		let (stream, continuation) = AsyncStream.makeStream(of: TypeFactsReport.self)
		_ = try await ConstructionMemoOracle.$observer.withValue(TaskLocalFunction { _, _, report in continuation.yield(report) }) {
			try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
		continuation.finish()
		var reports = [TypeFactsReport]()
		for await report in stream where report.root == "Root" && !report.forMockGeneration {
			reports.append(report)
		}
		let report = try #require(reports.last)

		#expect(report.dot.drawnByTree == """
		    Root -- "home: Home"
		    Root -- "office: Office"
		    "home: Home" -- "gadget: any Gadget"
		    "gadget: any Gadget" -- "homeBuilder: Instantiator<Home>"
		    "office: Office" -- "gadget: any Gadget"
		    "gadget: any Gadget" -- "homeBuilder: Instantiator<Home>"
		    "homeBuilder: Instantiator<Home>" -- "gadget: any Gadget"
		    "gadget: any Gadget" -- "homeBuilder: Instantiator<Home>"
		""")
		#expect(report.dot.unfolded == report.dot.drawnByTree)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsFillOfEveryPlaceInLaterPass_whenFillOfAnotherPlaceBuildsSeamAgain() async {
		// `LiveGadget`, which fills `Home`'s `gadget`, builds `Home` again, and that call passes on every fill of the call
		// that encloses it, by the key of each fill's place: every place gets a fill of its own from the next pass on.
		let (fills, error) = await fillsOfCalls { filesToDelete in
			_ = try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					parentDeclarations: [["@Instantiated let panel: Panel"], ["@Instantiated let panel: Panel"], ["@Instantiated let panel: Panel"]],
					panelDeclarations: ["@Instantiated let api: any Api"],
					liveApiDeclarations: [],
					homeDeclarations: ["@Instantiated let gadget: any Gadget"],
					appDeclarations: [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Instantiated let homeBuilder: Instantiator<Home>"])],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(error == nil)
		// The fill of `gadget` and two of the three places of `api`, then all four.
		#expect(fills.prefix(2).map { [$0.builtFillCount, $0.placeStoodForCount] } == [[3, 1], [4, 0]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsFillOfEveryPlace_whenFillsTreeCallsSeam() async {
		// `LiveApi` builds `Other`, a seam, so what its tree hands on is keyed by each fill's own place: no fill stands for
		// another place, and after the first such fill of a case the call keeps none to compare later places with.
		let (fills, error) = await fillsOfCalls { filesToDelete in
			_ = try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					parentDeclarations: Array(repeating: ["@Instantiated let panel: Panel"], count: 4),
					panelDeclarations: ["@Instantiated let api: any Api"],
					liveApiDeclarations: ["@Instantiated let other: Other"],
					appDeclarations: [seamFixtureType(named: "Other", isSeam: true, declarations: ["@Instantiated let token: Token"])],
					rowDeclarations: [],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(error == nil)
		#expect(fills.last.map { [$0.builtFillCount, $0.placeStoodForCount] } == [4, 0])
	}

	@Test(arguments: [false, true], [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_drawsEveryPlaceInDOTTree_whenAnotherPlacesFillStandsForPlace(buildsFillOfEveryPlace: Bool, placeStoodForIsLast: Bool) async throws {
		// One parent builds no `token`, so its place is judged with a fill of its own. `First`'s fill generates code, and
		// of the other two parents' fills the first stands for the second, which the call meets last or before the fill
		// that parent's place is judged with. The tree draws each of the four places beneath the call, in the order the
		// call meets them, each with `LiveApi`'s tree, whichever fills the call built.
		let parentWithoutToken = ["@Instantiated let panel: Panel"]
		let parentWithToken = ["@Instantiated let token: Token", "@Instantiated let panel: Panel"]
		let output = try await SeamFillSharing.$buildsFillOfEveryPlace.withValue(buildsFillOfEveryPlace) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					parentDeclarations: placeStoodForIsLast
						? [parentWithToken, parentWithoutToken, parentWithToken, parentWithToken]
						: [parentWithToken, parentWithToken, parentWithToken, parentWithoutToken],
					panelDeclarations: ["@Instantiated let api: any Api"],
					liveApiDeclarations: ["@Received let token: Token", "@Instantiated let row: Row"],
					rootDeclarations: ["@Instantiated let token: Token"],
					rowDeclarations: [],
				),
				integration: .moduleInfo,
				writesDOTTrees: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(output.modules["App"]?.dotTree == """
		graph SafeDI {
		    ranksep=2
		    Root -- "token: Token"
		    Root -- "home: Home"
		    "home: Home" -- "api: any Api"
		    "home: Home" -- "api: any Api"
		    "home: Home" -- "api: any Api"
		    "home: Home" -- "api: any Api"
		    "api: any Api" -- "row: Row"
		    "api: any Api" -- "row: Row"
		    "api: any Api" -- "row: Row"
		    "api: any Api" -- "row: Row"
		}
		""")
	}

	@Test(arguments: [false, true], [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_drawsPlaceStoodForAmongFillsThatHoldNoPlace_whenFillBuiltBeforeItHoldsPlaceOfItsOwn(buildsFillOfEveryPlace: Bool, buildsFillAfterPlaceStoodFor: Bool) async throws {
		// `MidSeam` calls `Home` and fills `agent` with `LiveAgent`, which holds a place of its own, `leaf`, so that fill
		// is drawn after the fills that hold none, though the call builds it first. `Second`'s fill of `api` stands for
		// `Third`'s, which is drawn after it and before `zed`'s, as its own fill would be, or, where `Home` has no `zed`
		// and the call builds no fill after it, before `agent`'s.
		let zedDeclarations = buildsFillAfterPlaceStoodFor ? ["@Instantiated let zed: any Zed"] : []
		let output = try await SeamFillSharing.$buildsFillOfEveryPlace.withValue(buildsFillOfEveryPlace) {
			try await executeSafeDIToolMultiModuleTest(
				modules: SafeDIToolSeamBuilderParameterTests.modules(
					feature: [
						"public protocol Agent {}",
						"public protocol Api {}",
						"public protocol Leaf {}",
						"public protocol Zed {}",
						seamFixtureType(named: "Row", declarations: []),
						seamFixtureType(named: "Panel", declarations: ["@Instantiated let api: any Api"]),
						seamFixtureType(named: "First", declarations: ["@Instantiated let panel: Panel"]),
						seamFixtureType(named: "Second", declarations: ["@Instantiated let panel: Panel"]),
						seamFixtureType(named: "Third", declarations: ["@Instantiated let panel: Panel"]),
						seamFixtureType(named: "Home", isSeam: true, declarations: [
							"@Instantiated let agent: any Agent",
							"@Instantiated let first: First",
							"@Instantiated let second: Second",
							"@Instantiated let third: Third",
						] + zedDeclarations),
					],
					app: [
						SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveAgent", fulfilling: "Agent", declarations: ["@Instantiated let leaf: any Leaf"]),
						SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Instantiated let row: Row"]),
						SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveZed", fulfilling: "Zed", declarations: []),
						seamFixtureType(named: "MidSeam", isSeam: true, declarations: ["@Instantiated let home: Home"]),
					],
				),
				integration: .moduleInfo,
				writesDOTTrees: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(output.modules["App"]?.dotTree == """
		graph SafeDI {
		    ranksep=2
		    MidSeam -- "home: Home"
		    "home: Home" -- "api: any Api"
		    "home: Home" -- "api: any Api"
		    "home: Home" -- "api: any Api"\(buildsFillAfterPlaceStoodFor ? "\n    \"home: Home\" -- \"zed: any Zed\"" : "")
		    "home: Home" -- "agent: any Agent"
		    "api: any Api" -- "row: Row"
		    "api: any Api" -- "row: Row"
		    "api: any Api" -- "row: Row"
		    "agent: any Agent" -- "leaf: any Leaf"
		}
		""")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Home`, a seam of `Feature` that declares `homeDeclarations` and then one type per entry of `parentDeclarations`,
	/// each declaring its entry, which builds `Panel`, with `panelDeclarations`; and `App`, whose `Root` calls `Home` and
	/// fills each `api` with `LiveApi`, which declares `liveApiDeclarations`, after it builds `rootDeclarations`.
	private static func modules(
		parentDeclarations: [[String]],
		panelDeclarations: [String],
		liveApiDeclarations: [String],
		homeDeclarations: [String] = [],
		appDeclarations: [String] = [],
		rootDeclarations: [String] = [],
		rowDeclarations: [String] = ["@Instantiated let api: any Api"],
		tokenDeclarations: [String] = [],
	) -> [ModuleFixture] {
		let parentNames = ["First", "Second", "Third", "Fourth"]
		var feature = [
			"public protocol Api {}",
			"public protocol Gadget {}",
			seamFixtureType(named: "Token", declarations: tokenDeclarations),
			seamFixtureType(named: "Row", declarations: rowDeclarations),
			seamFixtureType(named: "Panel", declarations: panelDeclarations),
		]
		for (name, declarations) in zip(parentNames, parentDeclarations) {
			feature.append(seamFixtureType(named: name, declarations: declarations))
		}
		feature.append(seamFixtureType(named: "Home", isSeam: true, declarations: homeDeclarations + zip(parentNames, parentDeclarations).map { name, _ in
			"@Instantiated let \(name.prefix(1).lowercased() + name.dropFirst()): \(name)"
		}))
		return SafeDIToolSeamBuilderParameterTests.modules(
			feature: feature,
			app: [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: liveApiDeclarations)]
				+ appDeclarations
				+ [seamFixtureType(named: "Root", isRoot: true, declarations: rootDeclarations + ["@Instantiated let home: Home"])],
		)
	}

	/// What each call that fills a place built while `body` ran, in the order the calls' generators were finished, and the
	/// error `body` threw, if any.
	private mutating func fillsOfCalls(_ body: (inout [URL]) async throws -> Void) async -> (fills: [SeamFillSharing.FillsOfCall], error: (any Error)?) {
		let (stream, continuation) = AsyncStream.makeStream(of: SeamFillSharing.FillsOfCall.self)
		var thrownError: (any Error)?
		var filesToDelete = filesToDelete
		do {
			try await SeamFillSharing.$observer.withValue(TaskLocalFunction { continuation.yield($0) }) {
				try await body(&filesToDelete)
			}
		} catch {
			thrownError = error
		}
		self.filesToDelete = filesToDelete
		continuation.finish()
		var fills = [SeamFillSharing.FillsOfCall]()
		for await fill in stream {
			fills.append(fill)
		}
		return (fills, thrownError)
	}
}
