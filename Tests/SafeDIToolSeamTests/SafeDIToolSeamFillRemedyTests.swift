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

/// The remedies of the errors a caller's module reports where it fills a seam's hole with a type that reads a value the
/// seam's builder is not handed. Each error's remedy is applied in a cell of its own, whose graph every module generates
/// and compiles, and whose seam build constructs the values the same graph builds inline, with no type a seam.
struct SafeDIToolSeamFillRemedyTests: ~Copyable {
	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: A value an inner seam's caller binds

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingReceiveOnlyIfAvailable_whenFillReceivesValueTheInnerSeamsCallerBindsOnlyIfAvailable() async {
		// `Feature` binds `db` where it calls `Inner`, whose builder it passes up, and `Live` receives `db` only if
		// available: the remedy receives it on `Inner` the same way, since a required receive of `db: Db?` there is
		// unfulfilled where `Feature` binds `db: Db`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Live.swift"]):11:5: error: `Live` receives `db: Db?`, which `Feature` builds where it calls `Inner`, but `Feature` passes the builder for `Inner`’s `api: any Api` (`api` of `apiBuilder`) on from its own caller, which cannot hand it `Feature`’s values. Declare `@Received(onlyIfAvailable: true) let db: Db?` on `Inner`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies, so `Feature` fills the builder itself.
			\(fixtures["Feature"]!["Feature.swift"]):11:5: note: `Feature` declares `db: Db` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.innerSeamModules(innerDeclarations: []), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenInnerSeamReceivesValueOnlyIfAvailableAsTheErrorSays() async throws {
		try await expectRemedyBuildsInlineValues(
			Self.innerSeamModules(innerDeclarations: ["@Received(onlyIfAvailable: true) public let db: Db?"]),
			probe: DifferentialValueProbe("Root()"),
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingReceiveOnlyIfAvailable_whenFillReceivesValueBoundOnTheWayToTheSeamBuiltAgainOnlyIfAvailable() async {
		// `Step` binds `cache` where it builds `Home` again, and that call passes `Home`'s builder on unchanged.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Live.swift"]):9:5: error: `Live` receives `cache: Cache?`, which `Home`’s tree builds where it instantiates `Home` again, but that call passes the builder `Home` takes for `Home`’s `api: any Api` on unchanged, so the caller that fills it cannot hand it those values. Declare `@Received(onlyIfAvailable: true) let cache: Cache?` on `Home`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies, so `Home` fills the builder itself.
			\(fixtures["Feature"]!["Step.swift"]):8:5: note: `Step` declares `cache: Cache` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.homeBuiltAgainModules(homeDeclarations: []), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenSeamBuiltAgainReceivesValueOnlyIfAvailableAsTheErrorSays() async throws {
		// The first `Home` hands `Live` `nil`, and the one `Step` builds again hands it `Step`'s `cache`, as inline.
		try await expectRemedyBuildsInlineValues(
			Self.homeBuiltAgainModules(homeDeclarations: ["@Received(onlyIfAvailable: true) public let cache: Cache?"]),
			probe: DifferentialValueProbe(
				name: "Live's cache in each Home",
				expression: """
				{ () -> [Bool] in
				    let home = Root().home
				    let step = home.stepBuilder.instantiate()
				    let again = step.homeBuilder.instantiate()
				    return [(home.api as? Live)?.cache == nil, (again.api as? Live)?.cache === step.cache]
				}()
				""",
			),
		)
	}

	// MARK: An instantiator the seam's tree builds after the place

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingOneHoleInPlaceOfBoth_whenFillReceivesInstantiatorWhoseTreeReceivesValuesTheSeamBinds() async {
		// `A` receives the `user` `SignedIn` forwards and the `bBuilder` it instantiates, so no type above `SignedIn` can
		// build `aBuilder`: one type of `App` that instantiates both, in place of both, puts `B` in the tree that builds it.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["B.swift"]):9:5: error: `B` receives `aBuilder: ErasedInstantiator<(), any AScreen>`, which `SignedIn`’s tree builds only after it calls the builder for `SignedIn`’s `bBuilder: ErasedInstantiator<(), any BScreen>` (`bBuilder` of `b_BScreenBuilder`), so SafeDI does not hand it to that builder. Declare `aBuilder` and `bBuilder` on one type of module `App` instead, and have `SignedIn` instantiate a protocol that type fulfills in their place, so that type’s tree builds both, or declare an @Instantiable type that fulfills `B` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["SignedIn.swift"]):10:5: note: `SignedIn` declares `aBuilder: ErasedInstantiator<(), any AScreen>` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.signedInModules(
					signedInDeclarations: [
						"@Forwarded public let user: User",
						"@Instantiated(fulfilledByType: \"A\") public let aBuilder: ErasedInstantiator<(), any AScreen>",
						"@Instantiated(fulfilledByType: \"B\") public let bBuilder: ErasedInstantiator<(), any BScreen>",
					],
					app: [],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenOneTypeOfTheFillingModuleInstantiatesBothInstantiatorsAsTheErrorSays() async throws {
		// `SignedIn` instantiates `pair`, which `App`'s `LivePair` fills, and whose tree builds both `aBuilder` and
		// `bBuilder`: `A` reads `SignedIn`'s `user`, and `B` the `aBuilder` beside it.
		try await expectRemedyBuildsInlineValues(
			Self.signedInModules(
				signedInDeclarations: ["@Forwarded public let user: User", "@Instantiated public let pair: any Pair"],
				app: [
					SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LivePair", fulfilling: "Pair", declarations: [
						"@Instantiated(fulfilledByType: \"A\") public let aBuilder: ErasedInstantiator<(), any AScreen>",
						"@Instantiated(fulfilledByType: \"B\") public let bBuilder: ErasedInstantiator<(), any BScreen>",
					]),
				],
			),
			probe: DifferentialValueProbe(
				name: "A's user and B's aBuilder",
				expression: """
				{ () -> [Bool] in
				    let user = User()
				    let signedIn = Root().signedInBuilder.instantiate(user)
				    let pair = signedIn.pair as? LivePair
				    let a = pair?.aBuilder.instantiate() as? A
				    let b = a?.bBuilder.instantiate() as? B
				    return [a?.user === user, b?.aBuilder.instantiate() is A]
				}()
				""",
			),
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingOnlyToFulfillTheHole_whenFillReceivesInstantiatorOnThePathWhoseTreeReceivesValueTheSeamForwards() async {
		// `Screen` receives the `user` `Home` forwards, so no type above `Home` can build `screenBuilder`, and it is on the
		// place's path, so nothing is built before it that could move beside it.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `screenBuilder: Instantiator<Screen>`, which `Home`’s tree is building where it calls the builder for `Screen`’s `api: any Api` (`api` of `apiBuilder`). Inline, `LiveApi` can get an instantiator of its own, made from the function `Home`’s initializer declares for `screenBuilder`, which code generated outside module `Feature` cannot refer to. Declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Home.swift"]):9:5: note: `Home` instantiates `screenBuilder: Instantiator<Screen>` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
						"public protocol Api {}",
						seamFixtureType(named: "User", isFinalClass: true, declarations: []),
						seamFixtureType(named: "Screen", declarations: ["@Received public let user: User", "@Instantiated public let api: any Api"]),
						seamFixtureType(named: "Home", isSeam: true, declarations: ["@Forwarded public let user: User", "@Instantiated public let screenBuilder: Instantiator<Screen>"]),
					]),
					ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
						"import Feature\n\n" + SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received public let screenBuilder: Instantiator<Screen>"]),
						"import Feature\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let homeBuilder: Instantiator<Home>"]),
					], dependencies: ["Feature"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: An instantiator a place's fill reads, whose own place's fill reads what the seam binds

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenOneTypeOfTheFillingModuleInstantiatesTwoHolesWhoseImplementationsReceiveEachOtherAsTheErrorSays() async throws {
		// The remedy of `SafeDIToolSeamReceivedBuilderCycleTests`' error where the implementations of two holes receive each
		// other's instantiators: `Screen` instantiates `pair`, which `App`'s `LivePair` fills, and whose tree builds both.
		try await expectRemedyBuildsInlineValues(
			Self.screenModules(
				screen: ["@Instantiated public let pair: any Pair"],
				app: [
					SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LivePair", fulfilling: "Pair", declarations: [Self.detailBuilder, Self.settingsBuilder]),
					Self.defaultDetail(declarations: [Self.receivedSettingsBuilder]),
					Self.defaultSettings(declarations: [Self.receivedDetailBuilder]),
				],
				root: ["@Instantiated public let screen: Screen"],
			),
			probe: DifferentialValueProbe(
				name: "the instantiator each implementation reads",
				expression: """
				{ () -> [Bool] in
				    let pair = Root().screen.pair as? LivePair
				    let detail = pair?.detailBuilder.instantiate() as? DefaultDetail
				    let settings = detail?.settingsBuilder.instantiate() as? DefaultSettings
				    return [detail != nil, settings?.detailBuilder.instantiate() is DefaultDetail]
				}()
				""",
			),
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingToInstantiateAboveTheSeam_whenFillReceivesHoleBuiltAfterItWhoseImplementationReceivesNothing() async {
		// `DefaultSettings`, which fills `settingsBuilder`, receives nothing, so a type above `Screen` can build
		// `settingsBuilder`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultDetail.swift"]):9:5: error: `DefaultDetail` receives `settingsBuilder: ErasedInstantiator<(), any Settings>`, which `Screen`’s tree builds only after it calls the builder for `Screen`’s `detailBuilder: ErasedInstantiator<(), any Detail>` (`detailBuilder` of `defaultDetail_DetailBuilder`), so SafeDI does not hand it to that builder. Instantiate `settingsBuilder` on a type above `Screen`, and receive it on `Screen` in place of its @Instantiated declaration, so that the caller’s tree builds it, or declare an @Instantiable type that fulfills `DefaultDetail` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Screen.swift"]):9:5: note: `Screen` declares `settingsBuilder: ErasedInstantiator<(), any Settings>` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.screenModules(
					screen: [Self.detailBuilder, Self.settingsBuilder],
					app: [Self.defaultDetail(declarations: [Self.receivedSettingsBuilder]), Self.defaultSettings(declarations: [])],
					root: ["@Instantiated public let screen: Screen"],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenTypeAboveTheSeamInstantiatesHoleWhoseImplementationReceivesNothingAsTheErrorSays() async throws {
		try await expectRemedyBuildsInlineValues(
			Self.screenModules(
				screen: [Self.detailBuilder, Self.receivedSettingsBuilder],
				app: [Self.defaultDetail(declarations: [Self.receivedSettingsBuilder]), Self.defaultSettings(declarations: [])],
				root: [Self.settingsBuilder, "@Instantiated public let screen: Screen"],
			),
			probe: DifferentialValueProbe(
				name: "the settings instantiator DefaultDetail reads",
				expression: "{ () -> [Bool] in [(Root().screen.detailBuilder.instantiate() as? DefaultDetail)?.settingsBuilder.instantiate() is DefaultSettings] }()",
			),
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenTypeAboveTheSeamInstantiatesHoleWhoseImplementationReceivesItAsTheErrorSays() async throws {
		// The remedy of `SafeDIToolSeamReceivedBuilderCycleTests`' error where a hole's implementation receives the hole's own
		// instantiator: `Root` instantiates `detailBuilder`, which `Screen` receives. The implementation reads the
		// instantiator that builds it, which the type above the seam then holds.
		try await expectRemedyBuildsInlineValues(
			Self.screenModules(
				screen: [Self.receivedDetailBuilder],
				app: [Self.defaultDetail(declarations: [Self.receivedDetailBuilder])],
				root: [Self.detailBuilder, "@Instantiated public let screen: Screen"],
			),
			probe: DifferentialValueProbe(
				name: "the detail instantiator DefaultDetail reads",
				expression: "{ () -> [Bool] in [(Root().screen.detailBuilder.instantiate() as? DefaultDetail)?.detailBuilder.instantiate() is DefaultDetail] }()",
			),
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingOnlyToFulfillTheHole_whenFillReceivesHoleBuiltAfterItThatAnotherModuleFills() async {
		// `Middle`'s `Outer` fills `settingsBuilder` with `DefaultSettings`, which receives the `token` `Outer` instantiates,
		// and passes `detailBuilder` up to `App`, whose `DefaultDetail` receives `settingsBuilder`. `App` sees no fill of
		// `settingsBuilder`, so it cannot tell that a type above `Screen`, or one type of `App` that declares both
		// instantiators, could build it: declaring both on such a type leads to an error about `token`, whose remedies `Feature`
		// and `Middle` cannot apply, since neither can name the other's types.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultDetail.swift"]):10:5: error: `DefaultDetail` receives `settingsBuilder: ErasedInstantiator<(), any Settings>`, which `Screen`’s tree builds only after it calls the builder for `Screen`’s `detailBuilder: ErasedInstantiator<(), any Detail>` (`detailBuilder` of `defaultDetail_DetailBuilder`), so SafeDI does not hand it to that builder. Declare an @Instantiable type that fulfills `DefaultDetail` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Screen.swift"]):9:5: note: `Screen` declares `settingsBuilder: ErasedInstantiator<(), any Settings>` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
						"public protocol Detail {}\npublic protocol Settings {}",
						seamFixtureType(named: "Screen", isSeam: true, declarations: [Self.detailBuilder, Self.settingsBuilder]),
					]),
					ModuleFixture(name: "Middle", packageName: "Mid", swiftFileContent: [
						seamFixtureType(named: "Token", isFinalClass: true, declarations: []),
						Self.defaultSettings(declarations: ["@Received public let token: Token"]),
						seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let token: Token", "@Instantiated public let screen: Screen"]),
					].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
					ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
						Self.defaultDetail(declarations: [Self.receivedSettingsBuilder]),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"]),
					].map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: A value declared on a cycle

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingReceiveOnTheTypeBuiltAgain_whenFillReadsValueTheCycleDeclaresAgain() async {
		// Inline, the `Step` that `Screen` builds again hands `Live` that `Screen`'s `cache`; a receive of `cache` on `Step`
		// makes each `Step` take its own level's.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Live.swift"]):9:5: error: `Live` receives `cache: Cache`, which `Screen` declares between where `Screen` instantiates `stepBuilder: Instantiator<Step>` and where `Screen` instantiates it again. Inline, the `Step` built again receives `Screen`’s `cache`, but SafeDI hands the builder for `Step`’s `api: any Api` (`api` of `apiBuilder`) the same values at every level of that cycle. Declare `@Received let cache: Cache` on `Step`, so each `Step` receives the `cache` of its own level and hands it on, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Screen.swift"]):8:5: note: `Screen` declares `cache: Cache` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.screenCycleModules(stepDeclarations: ["@Instantiated public let api: any Api"]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenTypeBuiltAgainReceivesValueAsTheErrorSays() async throws {
		try await expectRemedyBuildsInlineValues(
			Self.screenCycleModules(stepDeclarations: ["@Received public let cache: Cache", "@Instantiated public let api: any Api"]),
			probe: Self.liveCacheAtEachLevel(api: "api"),
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingReceiveOnTheTypeBuiltAgain_whenPlaceIsBeneathTheTypeBuiltAgain() async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Live.swift"]):9:5: error: `Live` receives `cache: Cache`, which `Screen` declares between where `Screen` instantiates `stepBuilder: Instantiator<Step>` and where `Screen` instantiates it again. Inline, the `Step` built again receives `Screen`’s `cache`, but SafeDI hands the builder for `Panel`’s `api: any Api` (`api` of `apiBuilder`) the same values at every level of that cycle. Declare `@Received let cache: Cache` on `Step`, so each `Step` receives the `cache` of its own level and hands it on, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Screen.swift"]):8:5: note: `Screen` declares `cache: Cache` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.screenCycleModules(stepDeclarations: ["@Instantiated public let panel: Panel"]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenTypeBuiltAgainAbovePlaceReceivesValueAsTheErrorSays() async throws {
		try await expectRemedyBuildsInlineValues(
			Self.screenCycleModules(stepDeclarations: ["@Received public let cache: Cache", "@Instantiated public let panel: Panel"]),
			probe: Self.liveCacheAtEachLevel(api: "panel.api"),
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenTypeTheSeamBuildsFirstReceivesValueOnlyIfAvailableAsTheErrorSays() async throws {
		// The `A` `Hub` builds has no `count` above it, and the one `B` builds again receives `B`'s, as `LiveApi` does
		// inline, the remedy the error offers where `LiveApi` receives `count` only if available.
		try await expectRemedyBuildsInlineValues(
			Self.hubCycleModules(aDeclarations: ["@Received(onlyIfAvailable: true) public let count: Int?"]),
			probe: DifferentialValueProbe(
				name: "A's api at each level",
				expression: """
				{ () -> [String] in
				    let a = Root().hub.aBuilder.instantiate("x")
				    let again = a.bBuilder.instantiate(2).aBuilder.instantiate("y")
				    return [a.api, again.api].map { "\\($0)" }
				}()
				""",
			),
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenTypeBuiltAgainReceivesValueANestedCyclePassesAsTheErrorSays() async throws {
		// `C` builds `B` again, so `B`'s function takes `count`, which `X` passes it first and `C` from then on; the error, of
		// `count` as a parameter of `B`'s function, offers the receive on `A`, the type `B` builds again.
		try await expectRemedyBuildsInlineValues(
			Self.nestedCycleModules(aDeclarations: ["@Received(onlyIfAvailable: true) public let count: Int?"]),
			probe: DifferentialValueProbe(
				name: "A's api at each level",
				expression: """
				{ () -> [String] in
				    let a = Root().hub.aBuilder.instantiate()
				    let b = a.xBuilder.instantiate(1).bBuilder.instantiate()
				    let again = b.aBuilder.instantiate()
				    let throughC = b.cBuilder.instantiate(2).bBuilder.instantiate().aBuilder.instantiate()
				    return [a.api, again.api, throughC.api].map { "\\($0)" }
				}()
				""",
			),
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingReceiveOnlyIfAvailableOnTheTypeBuiltAgain_whenFillReceivesValueTheCycleDeclaresOnlyIfAvailable() async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):11:5: error: `LiveApi` receives `count: Int?`, which `B` declares between where `Hub` instantiates `aBuilder: Instantiator<A>` and where `B` instantiates it again. Inline, the `A` built again receives `B`’s `count`, but SafeDI hands the builder for `A`’s `api: any Api` (`api` of `apiBuilder`) the same values at every level of that cycle. Declare `@Received(onlyIfAvailable: true) let count: Int?` on `A`, so each `A` receives the `count` of its own level and hands it on, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["B.swift"]):8:5: note: `B` declares `count: Int` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.hubCycleModules(aDeclarations: []), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingReceiveOnTheTypeBuiltAgain_whenFillReceivesValueANestedCyclePasses() async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `count: Int?`, which `B`’s builder function takes as a parameter between where `Hub` instantiates `aBuilder: Instantiator<A>` and where `B` instantiates it again, because a cycle inside `B`’s tree passes it (`C` declares `count: Int`). Inline, the `A` built again receives the `count` that parameter is passed, but SafeDI hands the builder for `A`’s `api: any Api` (`api` of `apiBuilder`) the same values at every level of that cycle. Declare `@Received(onlyIfAvailable: true) let count: Int?` on `A`, so each `A` receives the `count` of its own level and hands it on, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["C.swift"]):8:5: note: `C` declares `count: Int` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.nestedCycleModules(aDeclarations: []), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingReceiveOnTheConcreteTypeBuiltAgain_whenCycleClosesOnErasedInstantiator() async {
		// The cycle closes on an instantiator erased to `any StepScreen`: the receive goes on `Step`, the type it builds.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Live.swift"]):9:5: error: `Live` receives `cache: Cache`, which `Screen` declares between where `Screen` instantiates `stepBuilder: ErasedInstantiator<(), any StepScreen>` and where `Screen` instantiates it again. Inline, the `Step` built again receives `Screen`’s `cache`, but SafeDI hands the builder for `Step`’s `api: any Api` (`api` of `apiBuilder`) the same values at every level of that cycle. Declare `@Received let cache: Cache` on `Step`, so each `Step` receives the `cache` of its own level and hands it on, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Screen.swift"]):8:5: note: `Screen` declares `cache: Cache` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.screenCycleModules(stepBuilder: Self.erasedStepBuilder, stepDeclarations: ["@Instantiated public let api: any Api"]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenConcreteTypeBuiltAgainByErasedInstantiatorReceivesValueAsTheErrorSays() async throws {
		try await expectRemedyBuildsInlineValues(
			Self.screenCycleModules(stepBuilder: Self.erasedStepBuilder, stepDeclarations: ["@Received public let cache: Cache", "@Instantiated public let api: any Api"]),
			probe: Self.liveCacheAtEachLevel(api: "api", castingStepTo: " as! Step"),
		)
	}

	// MARK: A value bound outside a `@Sendable` function

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingInstantiatorBesideForwarding_whenSendableFunctionBuildsLazyWrapper() async {
		// A lazy wrapper is passed no forwarded value, so `K`, which would forward `n`, is built by an instantiator.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Live.swift"]):9:5: error: `Live` receives `n: Int`, which `Mid` forwards outside the `@Sendable` function that builds `k: SendableLazilyInstantiated<K>`, and SafeDI hands the builder for `K`’s `api: any Api` (`api` of `apiSendableBuilder`) only what that function binds. Declare `@Forwarded let n: Int` on `K` too, and `k` as `SendableInstantiator<K>`, so that function binds it, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Mid.swift"]):8:5: note: `Mid` declares `n: Int` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.midModules(
					k: ["@Instantiated public let api: any Api"],
					mid: ["@Forwarded public let n: Int", "@Instantiated public let k: SendableLazilyInstantiated<K>"],
					live: ["@Received public let n: Int"],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenLazyWrapperBecomesInstantiatorOfTypeThatForwardsValueAsTheErrorSays() async throws {
		try await expectRemedyBuildsInlineValues(
			Self.midModules(
				k: ["@Forwarded public let n: Int", "@Instantiated public let api: any Api"],
				mid: ["@Forwarded public let n: Int", "@Instantiated public let k: SendableInstantiator<K>"],
				live: ["@Received public let n: Int"],
			),
			probe: DifferentialValueProbe("{ () -> String in \"\\(Root().feature.midBuilder.instantiate(7).k.instantiate(9).api)\" }()"),
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingForwarding_whenValueBoundOutsideSendableFunctionReceivesForwardedValue() async {
		// `U` receives the `n` `Mid` forwards, so no type above `Feature` can build it: `K` takes it forwarded instead.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Live.swift"]):9:5: error: `Live` receives `u: U`, which `Mid` declares outside the `@Sendable` function that builds `k: SendableInstantiator<K>`, and SafeDI hands the builder for `K`’s `api: any Api` (`api` of `apiSendableBuilder`) only what that function binds. Declare `@Forwarded let u: U` on `K`, so that function binds it, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Mid.swift"]):10:5: note: `Mid` declares `u: U` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.midModules(
					k: ["@Instantiated public let api: any Api"],
					mid: ["@Forwarded public let n: Int", "@Instantiated public let u: U", "@Instantiated public let k: SendableInstantiator<K>"],
					live: ["@Received public let u: U"],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenTypeInsideSendableFunctionTakesValueForwardedAsTheErrorSays() async throws {
		try await expectRemedyBuildsInlineValues(
			Self.midModules(
				k: ["@Forwarded public let u: U", "@Instantiated public let api: any Api"],
				mid: ["@Forwarded public let n: Int", "@Instantiated public let u: U", "@Instantiated public let k: SendableInstantiator<K>"],
				live: ["@Received public let u: U"],
			),
			probe: DifferentialValueProbe("{ () -> String in let mid = Root().feature.midBuilder.instantiate(7); return \"\\(mid.k.instantiate(mid.u).api)\" }()"),
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenTypeInsideSendableFunctionTakesValueATypeOfTheSeamsTreeDeclaresForwardedAsTheErrorSays() async throws {
		// The remedy of `SafeDIToolSeamSendableScopeByTypeTests`' error where `DefaultWidget` requires the `part` that `Shell`,
		// a type of `Host`'s tree, instantiates outside the `@Sendable` function that builds `Panel`: receiving `part` on
		// `Host` would leave `Shell`'s declaration nearer, so `Panel` takes it forwarded instead.
		try await expectRemedyBuildsInlineValues(
			SafeDIToolSeamBuilderParameterTests.modules(
				feature: [
					"public protocol Widget {}",
					seamFixtureType(named: "Part", isFinalClass: true, declarations: []),
					seamFixtureType(named: "Panel", declarations: ["@Forwarded public let name: String", "@Forwarded public let part: Part", "@Instantiated public let widget: any Widget"]),
					seamFixtureType(named: "Shell", declarations: ["@Instantiated public let part: Part", "@Instantiated public let panelBuilder: SendableInstantiator<Panel>"]),
					seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated public let shell: Shell"]),
				],
				app: [
					SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Received public let part: Part"]),
					seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let host: Host"]),
				],
			),
			probe: DifferentialValueProbe(
				name: "the part DefaultWidget reads",
				expression: #"{ () -> [Bool] in let shell = Root().host.shell; return [(shell.panelBuilder.instantiate((name: "n", part: shell.part)).widget as? DefaultWidget)?.part === shell.part] }()"#,
			),
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenTypeASendableInstantiatorBuildsAgainTakesValueForwardedAsTheErrorSays() async throws {
		// The remedy of `SafeDIToolSeamSendableScopeByTypeTests`' error for the tangle where the `T` that `C` builds again
		// reads `C`'s `mark`, which `C` declares outside the `@Sendable` function that builds that `T`: `T` takes `mark`
		// forwarded, so each call of the function hands it its own.
		try await expectRemedyBuildsInlineValues(
			SafeDIToolSeamBuilderParameterTests.modules(
				feature: [
					"public protocol Api {}",
					seamFixtureType(named: "Mark", isFinalClass: true, declarations: []),
					seamFixtureType(named: "MarkReader", declarations: ["@Received(onlyIfAvailable: true) public let mark: Mark?"]),
					seamFixtureType(named: "T", declarations: ["@Forwarded public let mark: Mark", "@Instantiated public let reader: MarkReader", "@Instantiated public let cBuilder: Instantiator<C>", "@Instantiated public let api: any Api"]),
					seamFixtureType(named: "C", declarations: ["@Instantiated public let mark: Mark", "@Instantiated public let tBuilder: SendableInstantiator<T>"]),
					seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let tBuilder: SendableInstantiator<T>", "@Instantiated public let cBuilder: Instantiator<C>"]),
				],
				app: [
					SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received(onlyIfAvailable: true) public let mark: Mark?"]),
					seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let hub: Hub"]),
				],
			),
			probe: DifferentialValueProbe(
				name: "the mark LiveApi reads at each level",
				expression: """
				{ () -> [Bool] in
				    let mark = Mark()
				    let t = Root().hub.tBuilder.instantiate(mark)
				    let c = t.cBuilder.instantiate()
				    let tAgain = c.tBuilder.instantiate(c.mark)
				    return [(t.api as? LiveApi)?.mark === mark, (tAgain.api as? LiveApi)?.mark === c.mark]
				}()
				""",
			),
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingForwardingIntoInstantiator_whenValueBoundOutsideSendableLazyWrapperReceivesForwardedValue() async {
		// `U` receives the `n` `Mid` forwards, so no type above `Feature` can build it, and a lazy wrapper is passed no
		// forwarded value: `K` takes `u` forwarded, built by an instantiator.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Live.swift"]):9:5: error: `Live` receives `u: U`, which `Mid` declares outside the `@Sendable` function that builds `k: SendableLazilyInstantiated<K>`, and SafeDI hands the builder for `K`’s `api: any Api` (`api` of `apiSendableBuilder`) only what that function binds. Declare `@Forwarded let u: U` on `K`, and `k` as `SendableInstantiator<K>`, so that function binds it, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Mid.swift"]):10:5: note: `Mid` declares `u: U` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.midModules(
					k: ["@Instantiated public let api: any Api"],
					mid: ["@Forwarded public let n: Int", "@Instantiated public let u: U", "@Instantiated public let k: SendableLazilyInstantiated<K>"],
					live: ["@Received public let u: U"],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingForwarding_whenValueBoundOutsideSendableFunctionIsHoleWhoseImplementationReceivesForwardedValue() async {
		// `usage` is a hole, which `LiveUsage` fills and which receives the `n` `Mid` forwards, so no type above `Feature` can
		// build it: `K` takes it forwarded instead.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Live.swift"]):9:5: error: `Live` receives `usage: any Usage`, which `Mid` declares outside the `@Sendable` function that builds `k: SendableInstantiator<K>`, and SafeDI hands the builder for `K`’s `api: any Api` (`api` of `apiSendableBuilder`) only what that function binds. Declare `@Forwarded let usage: any Usage` on `K`, so that function binds it, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Mid.swift"]):10:5: note: `Mid` declares `usage: any Usage` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.midModules(
					k: ["@Instantiated public let api: any Api"],
					mid: ["@Forwarded public let n: Int", "@Instantiated public let usage: any Usage", "@Instantiated public let k: SendableInstantiator<K>"],
					live: ["@Received public let usage: any Usage"],
					app: [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveUsage", fulfilling: "Usage", declarations: ["@Received public let n: Int"])],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingOnlyToFulfillThePlace_whenValueIsBoundOutsideBuilderFunctionACycleMakesSendable() async {
		// `X`, which a `SendableInstantiator` builds, instantiates `K` again, so `K`'s builder function is `@Sendable`. `K` is
		// built by value: forwarding `n` into it would need an instantiator of it, which `X` cannot build by value.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Live.swift"]):9:5: error: `Live` receives `n: Int`, which `Mid` forwards outside the `@Sendable` function that builds `k: K`, and SafeDI hands the builder for `K`’s `api: any Api` (`api` of `apiSendableBuilder`) only what that function binds. Declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Mid.swift"]):8:5: note: `Mid` declares `n: Int` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.midModules(
					k: ["@Instantiated public let api: any Api", "@Instantiated public let xBuilder: SendableInstantiator<X>"],
					mid: ["@Forwarded public let n: Int", "@Instantiated public let k: K"],
					live: ["@Received public let n: Int"],
					feature: [seamFixtureType(named: "X", declarations: ["@Instantiated public let k: K"], conformances: ", Sendable")],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Core`, which declares `Api` and `Db`; `Inner`, a seam whose tree instantiates `api: any Api`, with
	/// `innerDeclarations` before it; `Feature`, a seam that instantiates `db` and then `inner`; and `App`, whose `Live`
	/// fills `Api` and receives `db` only if available, and whose root instantiates `feature`. `App` lists every module, so
	/// its root can build the tree inline.
	private static func innerSeamModules(innerDeclarations: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "Shop", swiftFileContent: ["public protocol Api {}", seamFixtureType(named: "Db", isFinalClass: true, declarations: [])]),
			ModuleFixture(name: "Inner", packageName: "Shop", swiftFileContent: ["import Core\n\n" + seamFixtureType(named: "Inner", isSeam: true, declarations: innerDeclarations + ["@Instantiated public let api: any Api"])], dependencies: ["Core"]),
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: ["import Core\nimport Inner\n\n" + seamFixtureType(named: "Feature", isSeam: true, declarations: ["@Instantiated public let db: Db", "@Instantiated public let inner: Inner"])], dependencies: ["Core", "Inner"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				"import Core\nimport Inner\nimport Feature\n\n" + SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "Live", fulfilling: "Api", declarations: ["@Received(onlyIfAvailable: true) public let db: Db?"]),
				"import Core\nimport Inner\nimport Feature\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let feature: Feature"]),
			], dependencies: ["Core", "Inner", "Feature"]),
		]
	}

	/// `Feature`, whose seam `Home`, with `homeDeclarations`, instantiates `api: any Api` and `Step`, which instantiates
	/// `cache` and `Home` again; and `App`, whose `Live` fills `Api` and receives `cache` only if available.
	private static func homeBuiltAgainModules(homeDeclarations: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Api {}",
				seamFixtureType(named: "Cache", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Home", isSeam: true, declarations: homeDeclarations + ["@Instantiated public let api: any Api", "@Instantiated public let stepBuilder: Instantiator<Step>"]),
				seamFixtureType(named: "Step", declarations: ["@Instantiated public let cache: Cache", "@Instantiated public let homeBuilder: Instantiator<Home>"]),
			]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				"import Feature\n\n" + SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "Live", fulfilling: "Api", declarations: ["@Received(onlyIfAvailable: true) public let cache: Cache?"]),
				"import Feature\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let home: Home"]),
			], dependencies: ["Feature"]),
		]
	}

	/// `Feature`, whose seam `SignedIn` holds `signedInDeclarations`, and whose `A`, which fulfills `AScreen`, receives
	/// `user` and `bBuilder`; and `App`, with `app`, whose `B` fulfills `BScreen` and receives `aBuilder`, and whose root
	/// instantiates an instantiator of `SignedIn`.
	private static func signedInModules(signedInDeclarations: [String], app: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol AScreen {}\npublic protocol BScreen {}\npublic protocol Pair {}",
				seamFixtureType(named: "User", isFinalClass: true, declarations: []),
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "A", fulfilling: "AScreen", declarations: ["@Received public let user: User", "@Received public let bBuilder: ErasedInstantiator<(), any BScreen>"]),
				seamFixtureType(named: "SignedIn", isSeam: true, declarations: signedInDeclarations),
			]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: (app + [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "B", fulfilling: "BScreen", declarations: ["@Received public let aBuilder: ErasedInstantiator<(), any AScreen>"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let signedInBuilder: Instantiator<SignedIn>"]),
			]).map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
	}

	/// `Feature`, whose seam `Home` instantiates `Screen`, which instantiates `cache` and then `stepBuilder`, an instantiator
	/// of `Step`, which fulfills `StepScreen`, with `stepDeclarations` and an instantiator of `Screen`, and `Panel`, which
	/// instantiates `api: any Api`; and `App`, whose `Live` fills `Api` and receives `cache`.
	private static func screenCycleModules(stepBuilder: String = "@Instantiated public let stepBuilder: Instantiator<Step>", stepDeclarations: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Api {}\npublic protocol StepScreen {}",
				seamFixtureType(named: "Cache", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Home", isSeam: true, declarations: ["@Instantiated public let screen: Screen"]),
				seamFixtureType(named: "Screen", declarations: ["@Instantiated public let cache: Cache", stepBuilder]),
				seamFixtureType(named: "Step", declarations: stepDeclarations + ["@Instantiated public let screenBuilder: Instantiator<Screen>"], conformances: ", StepScreen"),
				seamFixtureType(named: "Panel", declarations: ["@Instantiated public let api: any Api"]),
			]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				"import Feature\n\n" + SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "Live", fulfilling: "Api", declarations: ["@Received public let cache: Cache"]),
				"import Feature\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let home: Home"]),
			], dependencies: ["Feature"]),
		]
	}

	/// An instantiator of `Step` erased to `any StepScreen`, for `screenCycleModules`.
	private static let erasedStepBuilder = #"@Instantiated(fulfilledByType: "Step") public let stepBuilder: ErasedInstantiator<(), any StepScreen>"#

	/// Whether the `Live` beneath the `Step` that `Home`'s `Screen` builds, at `api` from the step, reads that `Screen`'s
	/// `cache`, and whether the one beneath the `Step` that `Screen` builds again reads that `Screen`'s. Each built step is
	/// cast as `castingStepTo` says.
	private static func liveCacheAtEachLevel(api: String, castingStepTo cast: String = "") -> DifferentialValueProbe {
		DifferentialValueProbe(
			name: "Live's cache at each level",
			expression: """
			{ () -> [Bool] in
			    let screen = Root().home.screen
			    let step = screen.stepBuilder.instantiate()\(cast)
			    let screenAgain = step.screenBuilder.instantiate()
			    let stepAgain = screenAgain.stepBuilder.instantiate()\(cast)
			    return [(step.\(api) as? Live)?.cache === screen.cache, (stepAgain.\(api) as? Live)?.cache === screenAgain.cache]
			}()
			""",
		)
	}

	/// `Feature`, with `feature`, whose seam instantiates an instantiator of `Mid`, with `mid`, and whose `K`, with `k`, and
	/// `U`, which receives `n`, are `Sendable`, as are its protocols `Api` and `Usage`; and `App`, with `app`, whose `Live`
	/// fills `Api` with `live`.
	private static func midModules(k: [String], mid: [String], live: [String], feature: [String] = [], app: [String] = []) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Api: Sendable {}\npublic protocol Usage: Sendable {}",
				seamFixtureType(named: "U", declarations: ["@Received public let n: Int"], conformances: ", Sendable"),
				seamFixtureType(named: "K", declarations: k, conformances: ", Sendable"),
				seamFixtureType(named: "Mid", declarations: mid),
				seamFixtureType(named: "Feature", isSeam: true, declarations: ["@Instantiated public let midBuilder: Instantiator<Mid>"]),
			] + feature),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: ([
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "Live", fulfilling: "Api", declarations: live),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let feature: Feature"]),
			] + app).map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
	}

	/// `Feature`, which declares `Detail`, `Settings` and `Pair`, and whose seam `Screen` holds `screen`; and `App`, which
	/// declares `app`, and whose root holds `root`.
	private static func screenModules(screen: [String], app: [String], root: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Detail {}\npublic protocol Settings {}\npublic protocol Pair {}",
				seamFixtureType(named: "Screen", isSeam: true, declarations: screen),
			]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: (app + [
				seamFixtureType(named: "Root", isRoot: true, declarations: root),
			]).map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
	}

	private static let detailBuilder = #"@Instantiated(fulfilledByType: "DefaultDetail") public let detailBuilder: ErasedInstantiator<(), any Detail>"#
	private static let settingsBuilder = #"@Instantiated(fulfilledByType: "DefaultSettings") public let settingsBuilder: ErasedInstantiator<(), any Settings>"#
	private static let receivedDetailBuilder = "@Received public let detailBuilder: ErasedInstantiator<(), any Detail>"
	private static let receivedSettingsBuilder = "@Received public let settingsBuilder: ErasedInstantiator<(), any Settings>"

	/// `App`'s `DefaultDetail`, which fulfills `Detail`, with `declarations`.
	private static func defaultDetail(declarations: [String]) -> String {
		seamFixtureType(named: "DefaultDetail", declarations: declarations, conformances: ", Detail")
	}

	/// `App`'s `DefaultSettings`, which fulfills `Settings`, with `declarations`.
	private static func defaultSettings(declarations: [String]) -> String {
		seamFixtureType(named: "DefaultSettings", declarations: declarations, conformances: ", Settings")
	}

	/// `Feature`, whose seam `Hub` instantiates an instantiator of `A`, with `aDeclarations`, which forwards `name` and
	/// instantiates `api: any Api` and an instantiator of `B`, which forwards `count` and instantiates `A` again; and `App`,
	/// whose `LiveApi` fills `Api` and receives `name` and `count` only if available.
	private static func hubCycleModules(aDeclarations: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Api {}",
				seamFixtureType(named: "A", declarations: ["@Forwarded public let name: String"] + aDeclarations + ["@Instantiated public let api: any Api", "@Instantiated public let bBuilder: Instantiator<B>"]),
				seamFixtureType(named: "B", declarations: ["@Forwarded public let count: Int", "@Instantiated public let aBuilder: Instantiator<A>"]),
				seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let aBuilder: Instantiator<A>"]),
			]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				"import Feature\n\n" + SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received(onlyIfAvailable: true) public let name: String?", "@Received(onlyIfAvailable: true) public let count: Int?"]),
				"import Feature\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let hub: Hub"]),
			], dependencies: ["Feature"]),
		]
	}

	/// `Feature`, whose seam `Hub` instantiates an instantiator of `A`, with `aDeclarations`, which instantiates
	/// `api: any Api` and an instantiator of `X`, which forwards `count` and instantiates an instantiator of `B`, which
	/// instantiates one of `C`, which forwards `count` and builds `B` again, and one of `A` again; and `App`, whose
	/// `LiveApi` fills `Api` and receives `count` only if available.
	private static func nestedCycleModules(aDeclarations: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Api {}",
				seamFixtureType(named: "A", declarations: aDeclarations + ["@Instantiated public let api: any Api", "@Instantiated public let xBuilder: Instantiator<X>"]),
				seamFixtureType(named: "X", declarations: ["@Forwarded public let count: Int", "@Instantiated public let bBuilder: Instantiator<B>"]),
				seamFixtureType(named: "B", declarations: ["@Received(onlyIfAvailable: true) public let count: Int?", "@Instantiated public let cBuilder: Instantiator<C>", "@Instantiated public let aBuilder: Instantiator<A>"]),
				seamFixtureType(named: "C", declarations: ["@Forwarded public let count: Int", "@Instantiated public let bBuilder: Instantiator<B>"]),
				seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let aBuilder: Instantiator<A>"]),
			]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				"import Feature\n\n" + SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received(onlyIfAvailable: true) public let count: Int?"]),
				"import Feature\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let hub: Hub"]),
			], dependencies: ["Feature"]),
		]
	}

	/// Expects `modules`, a remedied graph, to generate and compile in every module, and its seam build to construct the
	/// values that `probe` describes as the same graph does with no type a seam, which its root builds inline.
	private mutating func expectRemedyBuildsInlineValues(_ modules: [ModuleFixture], probe: DifferentialValueProbe, sourceLocation: SourceLocation = #_sourceLocation) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete, sourceLocation: sourceLocation)
		guard compileVerificationIsEnabled else { return }
		let inlineModules = modules.map { ModuleFixture(name: $0.name, packageName: $0.packageName, swiftFileContent: inlineFixture($0.swiftFileContent), dependencies: $0.dependencies) }
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete, sourceLocation: sourceLocation)
		try await expectDifferentialValuesAgree(
			feature: DifferentialValuePath(output: output, modules: modules),
			knownRight: DifferentialValuePath(output: inlineOutput, modules: inlineModules),
			probes: [probe],
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}
}
