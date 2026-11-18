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
