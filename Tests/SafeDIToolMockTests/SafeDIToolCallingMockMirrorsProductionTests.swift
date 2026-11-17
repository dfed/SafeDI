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

/// A calling mock, a generated `mock()` whose tree calls another module’s public mock, does what the same tree built for
/// production does: its production twin is the caller declared `@Instantiable(generateDependencyTree: true)`, with every
/// type whose public mock it calls declared a seam too. Where the twin reports an error, the mock reports the same
/// diagnostics; where the twin fills a place, the mock fills it and builds the twin’s values; where the twin takes a
/// builder, the mock takes one. Each test runs one fixture as the calling mock and, separately, as its twin.
struct SafeDIToolCallingMockMirrorsProductionTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try? FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – the twin’s errors, reported for the calling mock

	@Test(arguments: CallingMockCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTwinsError_whenCallingMocksFillReceivesValueOuterCalledTypeBuilds(caller: CallingMockCaller, calledTypes: CalledTypeDeclaration) async {
		let diagnostics = { (fixtures: [String: FixturePaths]) in
			"""
			\(fixtures["App"]!["AppTypes.swift"]):11:5: error: `LivePaymentService` receives `cart: Cart`, which `StoreScreen` builds where it calls `CheckoutScreen`, but `StoreScreen` passes the builder for `CheckoutScreen`’s `payments: any PaymentService` (`payments` of `paymentServiceBuilder`) on from its own caller, which cannot hand it `StoreScreen`’s values. Declare `@Received let cart: Cart` on `CheckoutScreen`, so the builder’s values struct carries it, or declare an @Instantiable type that fulfills `PaymentService` in module `Store` or a module it lists among its SafeDI dependencies, so `StoreScreen` fills the builder itself.
			\(fixtures["Store"]!["StoreTypes.swift"]):16:5: note: `StoreScreen` declares `cart: Cart` here.
			"""
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.w1Modules(caller: caller.attribute, callee: calledTypes.attribute), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.w1Modules(caller: Self.twinCaller, callee: Self.twinCalledTypes), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTwinsError_whenCallingMocksFillReceivesValueOuterCalledTypeBuildsUnderSwiftPackagePlugin() async {
		// The SwiftPM plugin scans every module before generating, which changes how the tool finds the files, not which
		// declarations it reports.
		let diagnostics = { (fixtures: [String: FixturePaths]) in
			"""
			\(NormalizedFilePath(fixtures["App"]!.compilerPath(of: "AppTypes.swift")).path):11:5: error: `LivePaymentService` receives `cart: Cart`, which `StoreScreen` builds where it calls `CheckoutScreen`, but `StoreScreen` passes the builder for `CheckoutScreen`’s `payments: any PaymentService` (`payments` of `paymentServiceBuilder`) on from its own caller, which cannot hand it `StoreScreen`’s values. Declare `@Received let cart: Cart` on `CheckoutScreen`, so the builder’s values struct carries it, or declare an @Instantiable type that fulfills `PaymentService` in module `Store` or a module it lists among its SafeDI dependencies, so `StoreScreen` fills the builder itself.
			\(NormalizedFilePath(fixtures["Store"]!.compilerPath(of: "StoreTypes.swift")).path):16:5: note: `StoreScreen` declares `cart: Cart` here.
			"""
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.w1Modules(caller: CallingMockCaller.internal.attribute, callee: Self.twinCalledTypes), integration: .swiftPackagePlugin, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.w1Modules(caller: Self.twinCaller, callee: Self.twinCalledTypes), integration: .swiftPackagePlugin, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: CallingMockCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTwinsError_whenCallingMocksFillReceivesValueMiddleCalledTypeBuilds(caller: CallingMockCaller, calledTypes: CalledTypeDeclaration) async {
		let diagnostics = { (fixtures: [String: FixturePaths]) in
			"""
			\(fixtures["App"]!["AppTypes.swift"]):11:5: error: `LivePaymentService` receives `cart: Cart`, which `OrderScreen` builds where it calls `CheckoutScreen`, but `OrderScreen` passes the builder for `CheckoutScreen`’s `payments: any PaymentService` (`payments` of `paymentServiceBuilder`) on from its own caller, which cannot hand it `OrderScreen`’s values. Declare `@Received let cart: Cart` on `CheckoutScreen`, so the builder’s values struct carries it, or declare an @Instantiable type that fulfills `PaymentService` in module `Store` or a module it lists among its SafeDI dependencies, so `OrderScreen` fills the builder itself.
			\(fixtures["Store"]!["StoreTypes.swift"]):16:5: note: `OrderScreen` declares `cart: Cart` here.
			"""
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.w1MiddleModules(caller: caller.attribute, callee: calledTypes.attribute), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.w1MiddleModules(caller: Self.twinCaller, callee: Self.twinCalledTypes), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: CallingMockCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTwinsError_whenCallingMocksFillReceivesValueOuterCalledTypeBuildsOnlyIfAvailable(caller: CallingMockCaller, calledTypes: CalledTypeDeclaration) async {
		let diagnostics = { (fixtures: [String: FixturePaths]) in
			"""
			\(fixtures["App"]!["AppTypes.swift"]):11:5: error: `LivePaymentService` receives `cart: Cart?`, which `StoreScreen` builds where it calls `CheckoutScreen`, but `StoreScreen` passes the builder for `CheckoutScreen`’s `payments: any PaymentService` (`payments` of `paymentServiceBuilder`) on from its own caller, which cannot hand it `StoreScreen`’s values. Declare `@Received let cart: Cart?` on `CheckoutScreen`, so the builder’s values struct carries it, or declare an @Instantiable type that fulfills `PaymentService` in module `Store` or a module it lists among its SafeDI dependencies, so `StoreScreen` fills the builder itself.
			\(fixtures["Store"]!["StoreTypes.swift"]):16:5: note: `StoreScreen` declares `cart: Cart` here.
			"""
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.w1OnlyIfAvailableModules(caller: caller.attribute, callee: calledTypes.attribute), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.w1OnlyIfAvailableModules(caller: Self.twinCaller, callee: Self.twinCalledTypes), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: CallingMockCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTwinsError_whenCallingMocksFillReceivesValueLoopBuildsOnPathToCall(caller: CallingMockCaller, calledTypes: CalledTypeDeclaration) async {
		let diagnostics = { (fixtures: [String: FixturePaths]) in
			"""
			\(fixtures["App"]!["AppTypes.swift"]):11:5: error: `LivePaymentService` receives `cart: Cart`, which `Page` builds on the path where `StoreScreen` calls `CheckoutScreen`, but `StoreScreen` passes the builder for `CheckoutScreen`’s `payments: any PaymentService` (`payments` of `paymentServiceBuilder`) on from its own caller, which cannot hand it that value. Declare `@Received let cart: Cart` on `CheckoutScreen`, so the builder’s values struct carries it, or declare an @Instantiable type that fulfills `PaymentService` in module `Store` or a module it lists among its SafeDI dependencies, so `StoreScreen` fills the builder itself.
			\(fixtures["Store"]!["StoreTypes.swift"]):17:5: note: `Page` declares `cart: Cart` here.
			"""
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.w1LoopCornerModules(caller: caller.attribute, callee: calledTypes.attribute), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.w1LoopCornerModules(caller: Self.twinCaller, callee: Self.twinCalledTypes), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: CallingMockCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTwinsError_whenCallingMocksAppOnlyScreenReceivesBuilderCalledTypeBuildsAfterCallingIt(caller: CallingMockCaller, calledTypes: CalledTypeDeclaration) async {
		let diagnostics = { (fixtures: [String: FixturePaths]) in
			"""
			\(fixtures["App"]!["AppTypes.swift"]):10:5: error: `AppSettings` receives `feedBuilder: ErasedInstantiator<(), any FeedPage>`, which `SignedIn`’s tree builds only after it calls the builder for `SignedIn`’s `settingsBuilder: ErasedInstantiator<(), any SettingsPage>` (`settingsBuilder` of `appSettings_SettingsPageBuilder`), so that builder’s values struct does not carry it. Instantiate `feedBuilder` on a type above `SignedIn`, and receive it on `SignedIn` in place of its @Instantiated declaration, so that the caller’s tree builds it, or declare an @Instantiable type that fulfills `AppSettings` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["FeatureTypes.swift"]):35:5: note: `SignedIn` declares `feedBuilder: ErasedInstantiator<(), any FeedPage>` here.
			"""
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.w4Modules(caller: caller.attribute, callee: calledTypes.attribute), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.w4Modules(caller: Self.twinCaller, callee: Self.twinCalledTypes), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: CallingMockCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTwinsCycle_whenCallingMocksAppOnlyScreenBuiltByValueReceivesBuilderOfScreenThatReceivesIt(caller: CallingMockCaller, calledTypes: CalledTypeDeclaration) async {
		let diagnostics = { (fixtures: [String: FixturePaths]) in
			"""
			\(fixtures["App"]!["AppTypes.swift"]):10:5: error: Dependency cycle: @Instantiated `feedBuilder: ErasedInstantiator<(), any FeedPage>` -> @Received `settings: any SettingsPage` -> @Received `feedBuilder: ErasedInstantiator<(), any FeedPage>`. `feedBuilder: ErasedInstantiator<(), any FeedPage>` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
			"""
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.w4ConstantCycleModules(caller: caller.attribute, callee: calledTypes.attribute), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.w4ConstantCycleModules(caller: Self.twinCaller, callee: Self.twinCalledTypes), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: CallingMockCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTwinsError_whenCallingMocksFillReadsValueOfLevelBetweenBuildsOfCalledType(caller: CallingMockCaller, calledTypes: CalledTypeDeclaration) async {
		let diagnostics = { (fixtures: [String: FixturePaths]) in
			"""
			\(fixtures["App"]!["AppTypes.swift"]):10:5: error: `LiveApi` receives `logger: Logger`, which `Home`’s tree builds where it instantiates `Home` again, but that call passes the builder `Home` takes for `Home`’s `api: any Api` on unchanged, so the caller that fills it cannot hand it those values. Declare `@Received let logger: Logger` on `Home`, so the builder’s values struct carries it, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies, so `Home` fills the builder itself.
			\(fixtures["Feature"]!["FeatureTypes.swift"]):22:5: note: `Loop` declares `logger: Logger` here.
			"""
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.seamBuiltAgainModules(caller: caller.attribute, callee: calledTypes.attribute), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.seamBuiltAgainModules(caller: Self.twinCaller, callee: Self.twinCalledTypes), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: CallingMockCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTwinsCycle_whenCallingMocksFillReceivesSiblingThatReceivesInnerCalledTypesBuilder(caller: CallingMockCaller, calledTypes: CalledTypeDeclaration) async {
		let diagnostics = { (fixtures: [String: FixturePaths]) in
			"""
			\(fixtures["FeatureModule"]!["FeatureModuleTypes.swift"]):14:5: error: Dependency cycle: @Instantiated `innerBuilder: Instantiator<Inner>` -> @Received `sibling: Sibling` -> @Received `innerBuilder: Instantiator<Inner>`. `innerBuilder: Instantiator<Inner>` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
			"""
		}
		await assertThrowsMultiModuleError(inModule: "Tests", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.loopThroughInnerBuilderModules(caller: caller.attribute, callee: calledTypes.attribute), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: "Tests", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.loopThroughInnerBuilderModules(caller: Self.twinCaller, callee: Self.twinCalledTypes), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Tests – each error’s remedies work for the calling mock

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: CallingMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesCallingMockAndItsCall_whenInnerCalledTypeReceivesOuterValueAsW1ErrorSays(caller: CallingMockCaller) async throws {
		// The first remedy of the error `LivePaymentService`’s receive of `StoreScreen`’s `cart` gets: `CheckoutScreen`
		// receives `cart`, so the builder’s values struct carries it.
		try await expectRemedyWorks(
			mock: Self.w1RemediedModules(caller: caller.attribute, callee: Self.twinCalledTypes),
			twin: Self.w1RemediedModules(caller: Self.twinCaller, callee: Self.twinCalledTypes),
			caller: caller,
			handWrittenCall: "import Checkout\nimport Store\n\nfunc callMock() {\n    _ = Root.mock()\n}\n",
		)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: CallingMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesCallingMockAndItsCall_whenFeedBuilderIsInstantiatedAboveCalledTypeAsW4ErrorSays(caller: CallingMockCaller) async throws {
		// The first remedy of W4’s error: `Root` instantiates `feedBuilder` and `SignedIn` receives it. The tool then asks for
		// `Feed` and its initializer to be `public`, with a fix-it, and `Root` takes what `Feed` receives and nothing above
		// it builds.
		try await expectRemedyWorks(
			mock: Self.w4RemediedModules(caller: caller.attribute, callee: Self.twinCalledTypes),
			twin: Self.w4RemediedModules(caller: Self.twinCaller, callee: Self.twinCalledTypes),
			caller: caller,
			handWrittenCall: "import Feature\nimport SafeDI\n\nstruct StubSettings: SettingsPage {}\n\nfunc callMock() {\n    _ = Root.mock(settingsBuilder: ErasedInstantiator<(), any SettingsPage> { StubSettings() }, user: User(name: \"name\"))\n}\n",
		)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: CallingMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesCallingMockAndItsCall_whenCalledTypeBuiltAgainReceivesValueAsErrorSays(caller: CallingMockCaller) async throws {
		// The first remedy of the error for the called type built again: `Home` receives `logger`.
		try await expectRemedyWorks(
			mock: Self.seamBuiltAgainRemediedModules(caller: caller.attribute, callee: Self.twinCalledTypes),
			twin: Self.seamBuiltAgainRemediedModules(caller: Self.twinCaller, callee: Self.twinCalledTypes),
			caller: caller,
			handWrittenCall: "import Feature\n\nfunc callMock() {\n    _ = Root.mock()\n}\n",
		)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: CallingMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesCallingMockAndItsCall_whenReceiveIsRemovedAsCycleErrorSays(caller: CallingMockCaller) async throws {
		// The first remedy of the dependency cycle: `AppSettings` no longer receives `feedBuilder`.
		try await expectRemedyWorks(
			mock: Self.w4ConstantCycleRemediedModules(caller: caller.attribute, callee: Self.twinCalledTypes),
			twin: Self.w4ConstantCycleRemediedModules(caller: Self.twinCaller, callee: Self.twinCalledTypes),
			caller: caller,
			handWrittenCall: "import Feature\n\nfunc callMock() {\n    _ = Root.mock()\n}\n",
		)
	}

	@Test(arguments: CallingMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_acceptsCallingMockAndTwin_whenCalledTypesModuleFulfillsPlaceAsSeamBuiltAgainErrorSays(caller: CallingMockCaller) async throws {
		// The second remedy of the error for the called type built again: `Feature` declares a type that fulfills `Api`.
		_ = try await executeSafeDIToolMultiModuleTest(modules: Self.seamBuiltAgainFulfilledInFeatureModules(caller: caller.attribute, callee: Self.twinCalledTypes), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		_ = try await executeSafeDIToolMultiModuleTest(modules: Self.seamBuiltAgainFulfilledInFeatureModules(caller: Self.twinCaller, callee: Self.twinCalledTypes), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
	}

	@Test(arguments: CallingMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_acceptsCallingMockAndTwin_whenCalledTypesModuleFulfillsSettingsAsW4ErrorSays(caller: CallingMockCaller) async throws {
		// The second remedy of W4’s error: `Feature` declares the type that fills `settingsBuilder`.
		_ = try await executeSafeDIToolMultiModuleTest(modules: Self.w4FulfilledInFeatureModules(caller: caller.attribute, callee: Self.twinCalledTypes), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		_ = try await executeSafeDIToolMultiModuleTest(modules: Self.w4FulfilledInFeatureModules(caller: Self.twinCaller, callee: Self.twinCalledTypes), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
	}

	@Test(arguments: CallingMockCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_buildsTwinsValues_whenReceiveIsRemovedAsCycleErrorSays(caller: CallingMockCaller, calledTypes: CalledTypeDeclaration) async throws {
		// The dependency cycle’s first remedy: `AppSettings` no longer receives `feedBuilder`. The calling mock and its twin
		// are accepted, the mock fills `settings` as the twin does, and what it builds equals what the twin builds.
		let result = try await GraphFuzzerCallingMockCheck.run(Self.graph(
			named: "the plain W4 cycle with its receive removed",
			mock: Self.w4ConstantCycleRemediedModules(caller: caller.attribute, callee: calledTypes.attribute),
			twin: Self.w4ConstantCycleRemediedModules(caller: Self.twinCaller, callee: Self.twinCalledTypes),
			callerTypeName: "Root",
			caller: caller,
			expectedTwinInitializerLabels: [],
			valueProbes: [DifferentialValueProbe(name: "Root", expression: "App.Root.mock()", knownRightExpression: "App.Root()")],
		), seed: 0)

		Self.expectFillsAsTwin(result)
	}

	@Test(arguments: CallingMockCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reachesAcceptedGraphWithTwinsValues_whenCycleErrorsOptionalReceiveIsFollowedThroughEachRemedy(caller: CallingMockCaller, calledTypes: CalledTypeDeclaration) async throws {
		// The dependency cycle’s second remedy, followed through every error it leads to: receiving `feedBuilder` only if
		// available draws W4’s error, whose first remedy draws two access errors, whose fix-its end in an accepted graph.
		// Each step’s text is the twin’s; the calling mock reports the same at each step.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["AppTypes.swift"]):10:5: error: Dependency cycle: @Instantiated `feedBuilder: ErasedInstantiator<(), any FeedPage>` -> @Received `settings: any SettingsPage` -> @Received `feedBuilder: ErasedInstantiator<(), any FeedPage>`. `feedBuilder: ErasedInstantiator<(), any FeedPage>` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.w4ConstantCycleModules(caller: Self.twinCaller, callee: Self.twinCalledTypes), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}

		// Step 1: `AppSettings` receives `feedBuilder` only if available, as the cycle error says.
		let w4Diagnostics = { (fixtures: [String: FixturePaths]) in
			"""
			\(fixtures["App"]!["AppTypes.swift"]):10:5: error: `AppSettings` receives `feedBuilder: ErasedInstantiator<(), any FeedPage>?`, which `SignedIn`’s tree builds only after it calls the builder for `SignedIn`’s `settings: any SettingsPage` (`settings` of `settingsPageBuilder`), so that builder’s values struct does not carry it. Instantiate `feedBuilder` on a type above `SignedIn`, and receive it on `SignedIn` in place of its @Instantiated declaration, so that the caller’s tree builds it, or declare an @Instantiable type that fulfills `SettingsPage` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["FeatureTypes.swift"]):35:5: note: `SignedIn` declares `feedBuilder: ErasedInstantiator<(), any FeedPage>` here.
			"""
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: w4Diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.w4ConstantCycleOptionalModules(caller: caller.attribute, callee: calledTypes.attribute), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: w4Diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.w4ConstantCycleOptionalModules(caller: Self.twinCaller, callee: Self.twinCalledTypes), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}

		// Step 2: `Root` instantiates `feedBuilder` and `SignedIn` receives it, as W4’s error says. `Feed` and its initializer
		// are `internal`, which the code built in `App` cannot reach; each error’s fix-it makes them `public`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["FeatureTypes.swift"]):16:1: error: `Feed` is `internal`, so the mock of `Root`, generated in module `App`, in another package, cannot construct it in the code SafeDI generates. Make `Feed` `public` to fix, or declare `Feed` `public` with `generateMock: .public`.
			\(fixtures["Feature"]!["FeatureTypes.swift"]):16:1-16:1: fixit: public\(" ")
			\(fixtures["Feature"]!["FeatureTypes.swift"]):17:5: error: `Feed`’s initializer is `internal`, so the mock of `Root`, generated in module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix, or declare `Feed` `public` with `generateMock: .public`.
			\(fixtures["Feature"]!["FeatureTypes.swift"]):17:5-17:5: fixit: public\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.w4ConstantCycleOptionalW4RemediedModules(caller: caller.attribute, callee: calledTypes.attribute), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["FeatureTypes.swift"]):16:1: error: `Feed` is `internal`, so module `App`, in another package, cannot construct it in the code SafeDI generates. Make `Feed` `public` to fix.
			\(fixtures["Feature"]!["FeatureTypes.swift"]):16:1-16:1: fixit: public\(" ")
			\(fixtures["Feature"]!["FeatureTypes.swift"]):17:5: error: `Feed`’s initializer is `internal`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
			\(fixtures["Feature"]!["FeatureTypes.swift"]):17:5-17:5: fixit: public\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.w4ConstantCycleOptionalW4RemediedModules(caller: Self.twinCaller, callee: Self.twinCalledTypes), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}

		// Step 3: the fix-its applied. The twin takes the `settings` and `user` `Feed` receives, which nothing above `Root`
		// builds; the mock takes `user` and builds `settings` itself (the `.public` mock also takes it, defaulted to `nil`), so
		// the twin is handed the `settings` the mock builds.
		let result = try await GraphFuzzerCallingMockCheck.run(Self.graph(
			named: "the plain W4 cycle followed through each remedy",
			mock: Self.w4ConstantCycleOptionalW4RemediedPublicFeedModules(caller: caller.attribute, callee: calledTypes.attribute),
			twin: Self.w4ConstantCycleOptionalW4RemediedPublicFeedModules(caller: Self.twinCaller, callee: Self.twinCalledTypes),
			callerTypeName: "Root",
			caller: caller,
			flatParameterLabels: caller == .public ? ["user", "settings"] : ["user"],
			expectedTwinInitializerLabels: ["settings", "user"],
			valueProbes: [DifferentialValueProbe(name: "Root", expression: "App.Root.mock(user: Feature.User(name: \"name\"))", knownRightExpression: "App.Root(__safeDI_settings: App.AppSettings(feedBuilder: nil), __safeDI_user: Feature.User(name: \"name\"))")],
		), seed: 0)

		Self.expectFillsAsTwin(result)
	}

	// MARK: Tests – fills where the twin fills, takes a builder where the twin takes one

	@Test(arguments: CallingMockCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_takesValueAndFillsPlace_whenCallingMocksFillReceivesValueNothingProvides(caller: CallingMockCaller, calledTypes: CalledTypeDeclaration) async throws {
		// The twin takes `token` and fills `Inner`’s `api` with `Fake(token:)`; the mock takes `token` as a parameter and
		// fills the place from it, building the twin’s values.
		let result = try await GraphFuzzerCallingMockCheck.run(Self.graph(
			named: "a fill receiving what nothing builds",
			mock: Self.tokenModules(caller: caller.attribute, callee: calledTypes.attribute),
			twin: Self.tokenModules(caller: Self.twinCaller, callee: Self.twinCalledTypes),
			callerTypeName: "Host",
			caller: caller,
			flatParameterLabels: ["token"],
			expectedTwinInitializerLabels: ["token"],
			valueProbes: [DifferentialValueProbe(name: "Host", expression: "Tests.Host.mock(token: Tests.Token())", knownRightExpression: "Tests.Host(__safeDI_token: Tests.Token())")],
		), seed: 0)

		Self.expectFillsAsTwin(result)
	}

	@Test(arguments: CallingMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesSameCallingMock_whenCalledTypesAreSeamsOrPublicMocksOnly(caller: CallingMockCaller) async throws {
		// Whether `Inner` and `Feature` are seams as well as public mocks changes nothing in the calling mock’s module: the
		// calling mock calls their public mocks either way.
		let besideSeams = try await executeSafeDIToolMultiModuleTest(modules: Self.tokenModules(caller: caller.attribute, callee: CalledTypeDeclaration.seamAndPublicMock.attribute), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		let publicMocksOnly = try await executeSafeDIToolMultiModuleTest(modules: Self.tokenModules(caller: caller.attribute, callee: CalledTypeDeclaration.publicMockOnly.attribute), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)

		#expect(besideSeams.modules["Tests"]?.generatedFiles == publicMocksOnly.modules["Tests"]?.generatedFiles)
	}

	@Test(arguments: CallingMockCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_fillsPlaceFromCallersOwnValue_whenTwinFillsIt(caller: CallingMockCaller, calledTypes: CalledTypeDeclaration) async throws {
		let result = try await GraphFuzzerCallingMockCheck.run(Self.graph(
			named: "a fill receiving the caller’s own value",
			mock: Self.ownValueModules(caller: caller.attribute, callee: calledTypes.attribute),
			twin: Self.ownValueModules(caller: Self.twinCaller, callee: Self.twinCalledTypes),
			callerTypeName: "Host",
			caller: caller,
			expectedTwinInitializerLabels: [],
			valueProbes: [DifferentialValueProbe(name: "Host", expression: "Tests.Host.mock()", knownRightExpression: "Tests.Host()")],
		), seed: 0)

		Self.expectFillsAsTwin(result)
	}

	@Test(arguments: CallingMockCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_fillsPlaceFromInnerCalledTypesValue_whenTwinFillsIt(caller: CallingMockCaller, calledTypes: CalledTypeDeclaration) async throws {
		// W1’s accepted neighbour: `LivePaymentService` receives `CheckoutScreen`’s own `session`, which the builder’s values
		// struct carries.
		let result = try await GraphFuzzerCallingMockCheck.run(Self.graph(
			named: "a fill receiving the inner called type’s value",
			mock: Self.w1InnerValueModules(caller: caller.attribute, callee: calledTypes.attribute),
			twin: Self.w1InnerValueModules(caller: Self.twinCaller, callee: Self.twinCalledTypes),
			callerTypeName: "Root",
			caller: caller,
			expectedTwinInitializerLabels: [],
			valueProbes: [DifferentialValueProbe(name: "Root", expression: "App.Root.mock()", knownRightExpression: "App.Root()")],
		), seed: 0)

		Self.expectFillsAsTwin(result)
	}

	@Test(arguments: CallingMockCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_fillsAppOnlyScreenFromForwardedValue_whenTwinFillsIt(caller: CallingMockCaller, calledTypes: CalledTypeDeclaration) async throws {
		// W4’s accepted neighbour: `AppSettings` receives the `user` `SignedIn` forwards.
		let result = try await GraphFuzzerCallingMockCheck.run(Self.graph(
			named: "an app-only screen receiving the called type’s forwarded value",
			mock: Self.w4ForwardedValueModules(caller: caller.attribute, callee: calledTypes.attribute),
			twin: Self.w4ForwardedValueModules(caller: Self.twinCaller, callee: Self.twinCalledTypes),
			callerTypeName: "Root",
			caller: caller,
			expectedTwinInitializerLabels: [],
			valueProbes: [DifferentialValueProbe(name: "Root", expression: "App.Root.mock()", knownRightExpression: "App.Root()")],
		), seed: 0)

		Self.expectFillsAsTwin(result)
	}

	@Test(arguments: CallingMockCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_fillsPlaceWithSeamAndPassesItsHoleUp_whenTwinDoes(caller: CallingMockCaller, calledTypes: CalledTypeDeclaration) async throws {
		// `Feature` fills `Inner`’s `service` with `GadgetSeam`, a seam whose own `gadget` nothing in `Mid` fulfills: the twin
		// takes `GadgetSeam`’s builder and fills `service`, so the mock does too.
		let result = try await GraphFuzzerCallingMockCheck.run(Self.graph(
			named: "a fill whose fulfiller is a seam that passes its own hole up",
			mock: Self.fulfilledBySeamModules(caller: caller.attribute, callee: calledTypes.attribute),
			twin: Self.fulfilledBySeamModules(caller: Self.twinCaller, callee: Self.twinCalledTypes),
			callerTypeName: "Feature",
			caller: caller,
			implementationIsVisible: false,
			expectedPassUpLabels: ["gadgetBuilder"],
			expectedTwinInitializerLabels: nil,
			valueProbes: [DifferentialValueProbe(name: "Feature", expression: "Mid.Feature.mock(gadgetBuilder: { Mid.StubGadget() })", knownRightExpression: "Mid.Feature(__safeDI_gadgetBuilder: .init(__safeDI_noScope: { Mid.StubGadget() }))")],
		), seed: 0)

		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.passUps.map(\.label) == ["gadgetBuilder"])
		#expect(result.failure == nil, "\(result.failure?.details ?? "")")
		#expect(result.comparedValues == compileVerificationIsEnabled)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The caller’s attribute line in its production twin.
	private static let twinCaller = "@Instantiable(generateDependencyTree: true)"
	/// A called type’s attribute line in the production twin: a seam as well as a public mock.
	private static let twinCalledTypes = CalledTypeDeclaration.seamAndPublicMock.attribute

	/// Expects `result`’s twin to have its graph’s intended outcome and the calling mock to mirror it: no place passed up,
	/// no failure, and, where compile verification is on, the twin’s values.
	private static func expectFillsAsTwin(_ result: GraphFuzzerCallingMockResult, sourceLocation: SourceLocation = #_sourceLocation) {
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")", sourceLocation: sourceLocation)
		#expect(result.passUps.map(\.label) == [], sourceLocation: sourceLocation)
		#expect(result.failure == nil, "\(result.failure?.details ?? "")", sourceLocation: sourceLocation)
		#expect(result.comparedValues == compileVerificationIsEnabled, sourceLocation: sourceLocation)
	}

	/// The calling-mock check’s graph of `mock` and `twin`, each module’s one file named `<Module>Types.swift`.
	private static func graph(
		named name: String,
		mock: [ModuleFixture],
		twin: [ModuleFixture],
		callerTypeName: String,
		caller: CallingMockCaller,
		flatParameterLabels: Set<String> = [],
		implementationIsVisible: Bool = true,
		expectedPassUpLabels: [String] = [],
		expectedTwinInitializerLabels: [String]?,
		valueProbes: [DifferentialValueProbe],
	) -> GraphFuzzerCallingMockGraph {
		GraphFuzzerCallingMockGraph(
			name: name,
			mockFiles: files(of: mock),
			twinFiles: files(of: twin),
			callerTypeName: callerTypeName,
			callerIsPublic: caller == .public,
			flatParameterLabels: flatParameterLabels,
			implementationIsVisible: implementationIsVisible,
			expectedTwinInitializerLabels: expectedTwinInitializerLabels,
			expectedPassUpLabels: expectedPassUpLabels,
			expectedTwinErrorSite: nil,
			valueProbes: valueProbes,
		)
	}

	private static func files(of modules: [ModuleFixture]) -> [GraphFuzzerCallingMockGraph.File] {
		modules.map { module in
			GraphFuzzerCallingMockGraph.File(module: module.name, dependencies: module.dependencies, content: module.swiftFileContentByFilePath["\(module.name)Types.swift"] ?? "")
		}
	}

	/// Expects a remedy to work for a calling mock: the tool accepts the remedied graph as the calling mock and as its twin,
	/// the calling mock’s module compiles, and so does `handWrittenCall`, a call of its `mock()`, in the caller’s module for
	/// an internal caller and in a module that depends on it for a `.public` one.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectRemedyWorks(mock: [ModuleFixture], twin: [ModuleFixture], caller: CallingMockCaller, handWrittenCall: String, sourceLocation: SourceLocation = #_sourceLocation) async throws {
		_ = try await executeSafeDIToolMultiModuleTest(modules: twin, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		let callerModule = mock[mock.count - 1]
		let modules: [ModuleFixture] = switch caller {
		case .internal:
			Array(mock.dropLast()) + [ModuleFixture(
				name: callerModule.name,
				packageName: callerModule.packageName,
				swiftFileContentByFilePath: callerModule.swiftFileContentByFilePath.merging(["HandWrittenCall.swift": handWrittenCall]) { first, _ in first },
				dependencies: callerModule.dependencies,
			)]
		case .public:
			mock + [ModuleFixture(
				name: "Consumer",
				packageName: "Consumer",
				swiftFileContentByFilePath: ["HandWrittenCall.swift": "import \(callerModule.name)\n" + handWrittenCall],
				dependencies: mock.map(\.name),
			)]
		}
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		#expect(compilation.failure == nil, "\(compilation.failure.map { "\($0)" } ?? "")", sourceLocation: sourceLocation)
	}

	// MARK: Fixtures

	/// W1: `LivePaymentService` fills `CheckoutScreen`’s place and receives the `cart` `StoreScreen`, which calls `CheckoutScreen`, builds (slice 4 helper’s W1-0).
	private static func w1Modules(caller: String, callee: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Checkout", packageName: "Checkout", swiftFileContentByFilePath: [
				"CheckoutTypes.swift": """
				import SafeDI

				public protocol PaymentService {}

				\(callee)
				public final class CheckoutScreen: Instantiable {
				    init(payments: any PaymentService) {
				        self.payments = payments
				    }

				    @Instantiated private let payments: any PaymentService
				}
				""",
			]),
			ModuleFixture(name: "Store", packageName: "Store", swiftFileContentByFilePath: [
				"StoreTypes.swift": """
				import SafeDI
				import Checkout

				@Instantiable
				public final class Cart: Instantiable {
				    public init() {}
				}

				\(callee)
				public final class StoreScreen: Instantiable {
				    init(cart: Cart, checkout: CheckoutScreen) {
				        self.cart = cart
				        self.checkout = checkout
				    }

				    @Instantiated private let cart: Cart
				    @Instantiated private let checkout: CheckoutScreen
				}
				""",
			], dependencies: ["Checkout"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"AppTypes.swift": """
				import SafeDI
				import Checkout
				import Store

				@Instantiable(fulfillingAdditionalTypes: [PaymentService.self])
				final class LivePaymentService: PaymentService, Instantiable {
				    init(cart: Cart) {
				        self.cart = cart
				    }

				    @Received private let cart: Cart
				}

				\(caller)
				public final class Root: Instantiable {
				    public init(store: StoreScreen) {
				        self.store = store
				    }

				    @Instantiated private let store: StoreScreen
				}
				""",
			], dependencies: ["Checkout", "Store"]),
		]
	}

	/// W1 three called types deep: the fill receives the `cart` of `OrderScreen`, the middle one (W1-h).
	private static func w1MiddleModules(caller: String, callee: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Checkout", packageName: "Checkout", swiftFileContentByFilePath: [
				"CheckoutTypes.swift": """
				import SafeDI

				public protocol PaymentService {}

				\(callee)
				public final class CheckoutScreen: Instantiable {
				    init(payments: any PaymentService) {
				        self.payments = payments
				    }

				    @Instantiated private let payments: any PaymentService
				}
				""",
			]),
			ModuleFixture(name: "Store", packageName: "Store", swiftFileContentByFilePath: [
				"StoreTypes.swift": """
				import SafeDI
				import Checkout

				@Instantiable
				public final class Cart: Instantiable {
				    public init() {}
				}

				\(callee)
				public final class OrderScreen: Instantiable {
				    init(cart: Cart, checkout: CheckoutScreen) {
				        self.cart = cart
				        self.checkout = checkout
				    }

				    @Instantiated private let cart: Cart
				    @Instantiated private let checkout: CheckoutScreen
				}

				\(callee)
				public final class StoreScreen: Instantiable {
				    init(order: OrderScreen) {
				        self.order = order
				    }

				    @Instantiated private let order: OrderScreen
				}
				""",
			], dependencies: ["Checkout"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"AppTypes.swift": """
				import SafeDI
				import Checkout
				import Store

				@Instantiable(fulfillingAdditionalTypes: [PaymentService.self])
				final class LivePaymentService: PaymentService, Instantiable {
				    init(cart: Cart) {
				        self.cart = cart
				    }

				    @Received private let cart: Cart
				}

				\(caller)
				public final class Root: Instantiable {
				    public init(store: StoreScreen) {
				        self.store = store
				    }

				    @Instantiated private let store: StoreScreen
				}
				""",
			], dependencies: ["Checkout", "Store"]),
		]
	}

	/// W1 with the fill receiving the outer `cart` only if available (W1-i).
	private static func w1OnlyIfAvailableModules(caller: String, callee: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Checkout", packageName: "Checkout", swiftFileContentByFilePath: [
				"CheckoutTypes.swift": """
				import SafeDI

				public protocol PaymentService {}

				\(callee)
				public final class CheckoutScreen: Instantiable {
				    init(payments: any PaymentService) {
				        self.payments = payments
				    }

				    @Instantiated private let payments: any PaymentService
				}
				""",
			]),
			ModuleFixture(name: "Store", packageName: "Store", swiftFileContentByFilePath: [
				"StoreTypes.swift": """
				import SafeDI
				import Checkout

				@Instantiable
				public final class Cart: Instantiable {
				    public init() {}
				}

				\(callee)
				public final class StoreScreen: Instantiable {
				    init(cart: Cart, checkout: CheckoutScreen) {
				        self.cart = cart
				        self.checkout = checkout
				    }

				    @Instantiated private let cart: Cart
				    @Instantiated private let checkout: CheckoutScreen
				}
				""",
			], dependencies: ["Checkout"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"AppTypes.swift": """
				import SafeDI
				import Checkout
				import Store

				@Instantiable(fulfillingAdditionalTypes: [PaymentService.self])
				final class LivePaymentService: PaymentService, Instantiable {
				    init(cart: Cart?) {
				        self.cart = cart
				    }

				    @Received(onlyIfAvailable: true) private let cart: Cart?
				}

				\(caller)
				public final class Root: Instantiable {
				    public init(store: StoreScreen) {
				        self.store = store
				    }

				    @Instantiated private let store: StoreScreen
				}
				""",
			], dependencies: ["Checkout", "Store"]),
		]
	}

	/// W1’s loop corner: `Page` builds `cart` and `checkout`, and builds itself again (W1-m).
	private static func w1LoopCornerModules(caller: String, callee: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Checkout", packageName: "Checkout", swiftFileContentByFilePath: [
				"CheckoutTypes.swift": """
				import SafeDI

				public protocol PaymentService {}

				\(callee)
				public final class CheckoutScreen: Instantiable {
				    init(payments: any PaymentService) {
				        self.payments = payments
				    }

				    @Instantiated private let payments: any PaymentService
				}
				""",
			]),
			ModuleFixture(name: "Store", packageName: "Store", swiftFileContentByFilePath: [
				"StoreTypes.swift": """
				import SafeDI
				import Checkout

				@Instantiable
				public final class Cart: Instantiable {
				    public init() {}
				}

				@Instantiable
				final class Page: Instantiable {
				    init(cart: Cart, checkout: CheckoutScreen, pageBuilder: Instantiator<Page>) {
				        self.cart = cart
				        self.checkout = checkout
				        self.pageBuilder = pageBuilder
				    }

				    @Instantiated private let cart: Cart
				    @Instantiated private let checkout: CheckoutScreen
				    @Instantiated private let pageBuilder: Instantiator<Page>
				}

				\(callee)
				public final class StoreScreen: Instantiable {
				    init(pageBuilder: Instantiator<Page>) {
				        self.pageBuilder = pageBuilder
				    }

				    @Instantiated private let pageBuilder: Instantiator<Page>
				}
				""",
			], dependencies: ["Checkout"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"AppTypes.swift": """
				import SafeDI
				import Checkout
				import Store

				@Instantiable(fulfillingAdditionalTypes: [PaymentService.self])
				final class LivePaymentService: PaymentService, Instantiable {
				    init(cart: Cart) {
				        self.cart = cart
				    }

				    @Received private let cart: Cart
				}

				\(caller)
				public final class Root: Instantiable {
				    public init(store: StoreScreen) {
				        self.store = store
				    }

				    @Instantiated private let store: StoreScreen
				}
				""",
			], dependencies: ["Checkout", "Store"]),
		]
	}

	/// W4: the app-only `AppSettings` in a loop of `SignedIn`’s screens receives `feedBuilder` (W4-0).
	private static func w4Modules(caller: String, callee: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContentByFilePath: [
				"FeatureTypes.swift": """
				import SafeDI

				public protocol FeedPage {}

				public protocol SettingsPage {}

				public struct User {
				    public init(name: String) {
				        self.name = name
				    }

				    public let name: String
				}

				@Instantiable
				final class Feed: FeedPage, Instantiable {
				    init(user: User, settingsBuilder: ErasedInstantiator<(), any SettingsPage>) {
				        self.user = user
				        self.settingsBuilder = settingsBuilder
				    }

				    @Received private let user: User
				    @Received private let settingsBuilder: ErasedInstantiator<(), any SettingsPage>
				}

				\(callee)
				public final class SignedIn: Instantiable {
				    init(user: User, feedBuilder: ErasedInstantiator<(), any FeedPage>, settingsBuilder: ErasedInstantiator<(), any SettingsPage>) {
				        self.user = user
				        self.feedBuilder = feedBuilder
				        self.settingsBuilder = settingsBuilder
				    }

				    @Forwarded private let user: User
				    @Instantiated(fulfilledByType: "Feed") private let feedBuilder: ErasedInstantiator<(), any FeedPage>
				    @Instantiated(fulfilledByType: "AppSettings") private let settingsBuilder: ErasedInstantiator<(), any SettingsPage>
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"AppTypes.swift": """
				import SafeDI
				import Feature

				@Instantiable
				final class AppSettings: SettingsPage, Instantiable {
				    init(feedBuilder: ErasedInstantiator<(), any FeedPage>) {
				        self.feedBuilder = feedBuilder
				    }

				    @Received private let feedBuilder: ErasedInstantiator<(), any FeedPage>
				}

				\(caller)
				public final class Root: Instantiable {
				    public init(signedInBuilder: Instantiator<SignedIn>) {
				        self.signedInBuilder = signedInBuilder
				    }

				    @Instantiated private let signedInBuilder: Instantiator<SignedIn>
				}
				""",
			], dependencies: ["Feature"]),
		]
	}

	/// The plain W4 cycle: `SignedIn` builds `AppSettings` by value, and `Feed` receives it.
	private static func w4ConstantCycleModules(caller: String, callee: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContentByFilePath: [
				"FeatureTypes.swift": """
				import SafeDI

				public protocol FeedPage {}

				public protocol SettingsPage {}

				public struct User {
				    public init(name: String) {
				        self.name = name
				    }

				    public let name: String
				}

				@Instantiable
				final class Feed: FeedPage, Instantiable {
				    init(user: User, settings: any SettingsPage) {
				        self.user = user
				        self.settings = settings
				    }

				    @Received private let user: User
				    @Received private let settings: any SettingsPage
				}

				\(callee)
				public final class SignedIn: Instantiable {
				    init(user: User, feedBuilder: ErasedInstantiator<(), any FeedPage>, settings: any SettingsPage) {
				        self.user = user
				        self.feedBuilder = feedBuilder
				        self.settings = settings
				    }

				    @Forwarded private let user: User
				    @Instantiated(fulfilledByType: "Feed") private let feedBuilder: ErasedInstantiator<(), any FeedPage>
				    @Instantiated private let settings: any SettingsPage
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"AppTypes.swift": """
				import SafeDI
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [SettingsPage.self])
				final class AppSettings: SettingsPage, Instantiable {
				    init(feedBuilder: ErasedInstantiator<(), any FeedPage>) {
				        self.feedBuilder = feedBuilder
				    }

				    @Received private let feedBuilder: ErasedInstantiator<(), any FeedPage>
				}

				\(caller)
				public final class Root: Instantiable {
				    public init(signedInBuilder: Instantiator<SignedIn>) {
				        self.signedInBuilder = signedInBuilder
				    }

				    @Instantiated private let signedInBuilder: Instantiator<SignedIn>
				}
				""",
			], dependencies: ["Feature"]),
		]
	}

	/// A called type built again by its own tree, whose fill reads the `logger` of the level between (L5x).
	private static func seamBuiltAgainModules(caller: String, callee: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContentByFilePath: [
				"FeatureTypes.swift": """
				import SafeDI

				public protocol Api {}

				@Instantiable
				public final class Cache: Instantiable {
				    public init() {}
				}

				@Instantiable
				public final class Logger: Instantiable {
				    public init() {}
				}

				@Instantiable
				final class Loop: Instantiable {
				    init(logger: Logger, homeBuilder: Instantiator<Home>) {
				        self.logger = logger
				        self.homeBuilder = homeBuilder
				    }

				    @Instantiated private let logger: Logger
				    @Instantiated private let homeBuilder: Instantiator<Home>
				}

				\(callee)
				public final class Home: Instantiable {
				    init(api: any Api, loopBuilder: Instantiator<Loop>) {
				        self.api = api
				        self.loopBuilder = loopBuilder
				    }

				    @Instantiated private let api: any Api
				    @Instantiated private let loopBuilder: Instantiator<Loop>
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"AppTypes.swift": """
				import SafeDI
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				final class LiveApi: Api, Instantiable {
				    init(logger: Logger) {
				        self.logger = logger
				    }

				    @Received private let logger: Logger
				}

				\(caller)
				public final class Root: Instantiable {
				    public init(logger: Logger, home: Home) {
				        self.logger = logger
				        self.home = home
				    }

				    @Instantiated private let logger: Logger
				    @Instantiated private let home: Home
				}
				""",
			], dependencies: ["Feature"]),
		]
	}

	/// A loop through an inner called type’s builder: `Sibling` receives `innerBuilder`, and the fill receives `Sibling`.
	private static func loopThroughInnerBuilderModules(caller: String, callee: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "InnerModule", packageName: "InnerModule", swiftFileContentByFilePath: [
				"InnerModuleTypes.swift": """
				import SafeDI

				public protocol Api: AnyObject {}

				\(callee)
				public final class Inner: Instantiable {
				    init(api: any Api) { self.api = api }
				    @Instantiated public let api: any Api
				}
				""",
			]),
			ModuleFixture(name: "FeatureModule", packageName: "FeatureModule", swiftFileContentByFilePath: [
				"FeatureModuleTypes.swift": """
				import SafeDI
				import InnerModule

				\(callee)
				public final class Feature: Instantiable {
				    init(innerBuilder: Instantiator<Inner>, sibling: Sibling) { self.innerBuilder = innerBuilder; self.sibling = sibling }
				    @Instantiated public let innerBuilder: Instantiator<Inner>
				    @Instantiated public let sibling: Sibling
				}

				@Instantiable
				public final class Sibling: Instantiable {
				    init(innerBuilder: Instantiator<Inner>) { self.innerBuilder = innerBuilder }
				    @Received let innerBuilder: Instantiator<Inner>
				}
				""",
			], dependencies: ["InnerModule"]),
			ModuleFixture(name: "Tests", packageName: "Tests", swiftFileContentByFilePath: [
				"TestsTypes.swift": """
				import SafeDI
				import InnerModule
				import FeatureModule

				@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
				final class Fake: Api, Instantiable {
				    init(sibling: Sibling) { self.sibling = sibling }
				    @Received let sibling: Sibling
				}

				\(caller)
				public final class Host: Instantiable {
				    public init(feature: Feature) { self.feature = feature }
				    @Instantiated let feature: Feature
				}
				""",
			], dependencies: ["InnerModule", "FeatureModule"]),
		]
	}

	/// W1 with its first remedy applied: `CheckoutScreen` receives `cart` (`Cart` moves to `Checkout`, which must name it).
	private static func w1RemediedModules(caller: String, callee: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Checkout", packageName: "Checkout", swiftFileContentByFilePath: [
				"CheckoutTypes.swift": """
				import SafeDI

				public protocol PaymentService {}

				@Instantiable
				public final class Cart: Instantiable {
				    public init() {}
				}

				\(callee)
				public final class CheckoutScreen: Instantiable {
				    init(cart: Cart, payments: any PaymentService) {
				        self.cart = cart
				        self.payments = payments
				    }

				    @Received private let cart: Cart
				    @Instantiated private let payments: any PaymentService
				}
				""",
			]),
			ModuleFixture(name: "Store", packageName: "Store", swiftFileContentByFilePath: [
				"StoreTypes.swift": """
				import SafeDI
				import Checkout

				\(callee)
				public final class StoreScreen: Instantiable {
				    init(cart: Cart, checkout: CheckoutScreen) {
				        self.cart = cart
				        self.checkout = checkout
				    }

				    @Instantiated private let cart: Cart
				    @Instantiated private let checkout: CheckoutScreen
				}
				""",
			], dependencies: ["Checkout"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"AppTypes.swift": """
				import SafeDI
				import Checkout
				import Store

				@Instantiable(fulfillingAdditionalTypes: [PaymentService.self])
				final class LivePaymentService: PaymentService, Instantiable {
				    init(cart: Cart) {
				        self.cart = cart
				    }

				    @Received private let cart: Cart
				}

				\(caller)
				public final class Root: Instantiable {
				    public init(store: StoreScreen) {
				        self.store = store
				    }

				    @Instantiated private let store: StoreScreen
				}
				""",
			], dependencies: ["Checkout", "Store"]),
		]
	}

	/// W4 with its first remedy applied (`feedBuilder` instantiated on `Root`, received on `SignedIn`), and the access fix-its the tool then names (`Feed` and its initializer `public`).
	private static func w4RemediedModules(caller: String, callee: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContentByFilePath: [
				"FeatureTypes.swift": """
				import SafeDI

				public protocol FeedPage {}

				public protocol SettingsPage {}

				public struct User {
				    public init(name: String) {
				        self.name = name
				    }

				    public let name: String
				}

				@Instantiable
				public final class Feed: FeedPage, Instantiable {
				    public init(user: User, settingsBuilder: ErasedInstantiator<(), any SettingsPage>) {
				        self.user = user
				        self.settingsBuilder = settingsBuilder
				    }

				    @Received private let user: User
				    @Received private let settingsBuilder: ErasedInstantiator<(), any SettingsPage>
				}

				\(callee)
				public final class SignedIn: Instantiable {
				    init(user: User, feedBuilder: ErasedInstantiator<(), any FeedPage>, settingsBuilder: ErasedInstantiator<(), any SettingsPage>) {
				        self.user = user
				        self.feedBuilder = feedBuilder
				        self.settingsBuilder = settingsBuilder
				    }

				    @Forwarded private let user: User
				    @Received private let feedBuilder: ErasedInstantiator<(), any FeedPage>
				    @Instantiated(fulfilledByType: "AppSettings") private let settingsBuilder: ErasedInstantiator<(), any SettingsPage>
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"AppTypes.swift": """
				import SafeDI
				import Feature

				@Instantiable
				final class AppSettings: SettingsPage, Instantiable {
				    init(feedBuilder: ErasedInstantiator<(), any FeedPage>) {
				        self.feedBuilder = feedBuilder
				    }

				    @Received private let feedBuilder: ErasedInstantiator<(), any FeedPage>
				}

				\(caller)
				public final class Root: Instantiable {
				    public init(feedBuilder: ErasedInstantiator<(), any FeedPage>, signedInBuilder: Instantiator<SignedIn>) {
				        self.feedBuilder = feedBuilder
				        self.signedInBuilder = signedInBuilder
				    }

				    @Instantiated(fulfilledByType: "Feed") private let feedBuilder: ErasedInstantiator<(), any FeedPage>
				    @Instantiated private let signedInBuilder: Instantiator<SignedIn>
				}
				""",
			], dependencies: ["Feature"]),
		]
	}

	/// W4 with its second remedy applied: `Feature` declares the type that fills `settingsBuilder`.
	private static func w4FulfilledInFeatureModules(caller: String, callee: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContentByFilePath: [
				"FeatureTypes.swift": """
				import SafeDI

				public protocol FeedPage {}

				public protocol SettingsPage {}

				public struct User {
				    public init(name: String) {
				        self.name = name
				    }

				    public let name: String
				}

				@Instantiable
				final class Feed: FeedPage, Instantiable {
				    init(user: User, settingsBuilder: ErasedInstantiator<(), any SettingsPage>) {
				        self.user = user
				        self.settingsBuilder = settingsBuilder
				    }

				    @Received private let user: User
				    @Received private let settingsBuilder: ErasedInstantiator<(), any SettingsPage>
				}

				@Instantiable
				final class AppSettings: SettingsPage, Instantiable {
				    init(feedBuilder: ErasedInstantiator<(), any FeedPage>) {
				        self.feedBuilder = feedBuilder
				    }

				    @Received private let feedBuilder: ErasedInstantiator<(), any FeedPage>
				}

				\(callee)
				public final class SignedIn: Instantiable {
				    init(user: User, feedBuilder: ErasedInstantiator<(), any FeedPage>, settingsBuilder: ErasedInstantiator<(), any SettingsPage>) {
				        self.user = user
				        self.feedBuilder = feedBuilder
				        self.settingsBuilder = settingsBuilder
				    }

				    @Forwarded private let user: User
				    @Instantiated(fulfilledByType: "Feed") private let feedBuilder: ErasedInstantiator<(), any FeedPage>
				    @Instantiated(fulfilledByType: "AppSettings") private let settingsBuilder: ErasedInstantiator<(), any SettingsPage>
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"AppTypes.swift": """
				import SafeDI
				import Feature

				\(caller)
				public final class Root: Instantiable {
				    public init(signedInBuilder: Instantiator<SignedIn>) {
				        self.signedInBuilder = signedInBuilder
				    }

				    @Instantiated private let signedInBuilder: Instantiator<SignedIn>
				}
				""",
			], dependencies: ["Feature"]),
		]
	}

	/// The plain W4 cycle with its first remedy applied: `AppSettings` no longer receives `feedBuilder`.
	private static func w4ConstantCycleRemediedModules(caller: String, callee: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContentByFilePath: [
				"FeatureTypes.swift": """
				import SafeDI

				public protocol FeedPage {}

				public protocol SettingsPage {}

				public struct User {
				    public init(name: String) {
				        self.name = name
				    }

				    public let name: String
				}

				@Instantiable
				final class Feed: FeedPage, Instantiable {
				    init(user: User, settings: any SettingsPage) {
				        self.user = user
				        self.settings = settings
				    }

				    @Received private let user: User
				    @Received private let settings: any SettingsPage
				}

				\(callee)
				public final class SignedIn: Instantiable {
				    init(user: User, feedBuilder: ErasedInstantiator<(), any FeedPage>, settings: any SettingsPage) {
				        self.user = user
				        self.feedBuilder = feedBuilder
				        self.settings = settings
				    }

				    @Forwarded private let user: User
				    @Instantiated(fulfilledByType: "Feed") private let feedBuilder: ErasedInstantiator<(), any FeedPage>
				    @Instantiated private let settings: any SettingsPage
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"AppTypes.swift": """
				import SafeDI
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [SettingsPage.self])
				final class AppSettings: SettingsPage, Instantiable {
				    init() {}
				}

				\(caller)
				public final class Root: Instantiable {
				    public init(signedInBuilder: Instantiator<SignedIn>) {
				        self.signedInBuilder = signedInBuilder
				    }

				    @Instantiated private let signedInBuilder: Instantiator<SignedIn>
				}
				""",
			], dependencies: ["Feature"]),
		]
	}

	/// The plain W4 cycle with its second remedy applied: `AppSettings` receives `feedBuilder` only if available.
	private static func w4ConstantCycleOptionalModules(caller: String, callee: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContentByFilePath: [
				"FeatureTypes.swift": """
				import SafeDI

				public protocol FeedPage {}

				public protocol SettingsPage {}

				public struct User {
				    public init(name: String) {
				        self.name = name
				    }

				    public let name: String
				}

				@Instantiable
				final class Feed: FeedPage, Instantiable {
				    init(user: User, settings: any SettingsPage) {
				        self.user = user
				        self.settings = settings
				    }

				    @Received private let user: User
				    @Received private let settings: any SettingsPage
				}

				\(callee)
				public final class SignedIn: Instantiable {
				    init(user: User, feedBuilder: ErasedInstantiator<(), any FeedPage>, settings: any SettingsPage) {
				        self.user = user
				        self.feedBuilder = feedBuilder
				        self.settings = settings
				    }

				    @Forwarded private let user: User
				    @Instantiated(fulfilledByType: "Feed") private let feedBuilder: ErasedInstantiator<(), any FeedPage>
				    @Instantiated private let settings: any SettingsPage
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"AppTypes.swift": """
				import SafeDI
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [SettingsPage.self])
				final class AppSettings: SettingsPage, Instantiable {
				    init(feedBuilder: ErasedInstantiator<(), any FeedPage>?) {
				        self.feedBuilder = feedBuilder
				    }

				    @Received(onlyIfAvailable: true) private let feedBuilder: ErasedInstantiator<(), any FeedPage>?
				}

				\(caller)
				public final class Root: Instantiable {
				    public init(signedInBuilder: Instantiator<SignedIn>) {
				        self.signedInBuilder = signedInBuilder
				    }

				    @Instantiated private let signedInBuilder: Instantiator<SignedIn>
				}
				""",
			], dependencies: ["Feature"]),
		]
	}

	/// The plain W4 cycle with its second remedy applied, then W4’s first remedy as worded: `Root` instantiates `feedBuilder`,
	/// and `SignedIn` receives it in place of its `@Instantiated` declaration.
	private static func w4ConstantCycleOptionalW4RemediedModules(caller: String, callee: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContentByFilePath: [
				"FeatureTypes.swift": """
				import SafeDI

				public protocol FeedPage {}

				public protocol SettingsPage {}

				public struct User {
				    public init(name: String) {
				        self.name = name
				    }

				    public let name: String
				}

				@Instantiable
				final class Feed: FeedPage, Instantiable {
				    init(user: User, settings: any SettingsPage) {
				        self.user = user
				        self.settings = settings
				    }

				    @Received private let user: User
				    @Received private let settings: any SettingsPage
				}

				\(callee)
				public final class SignedIn: Instantiable {
				    init(user: User, feedBuilder: ErasedInstantiator<(), any FeedPage>, settings: any SettingsPage) {
				        self.user = user
				        self.feedBuilder = feedBuilder
				        self.settings = settings
				    }

				    @Forwarded private let user: User
				    @Received private let feedBuilder: ErasedInstantiator<(), any FeedPage>
				    @Instantiated private let settings: any SettingsPage
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"AppTypes.swift": """
				import SafeDI
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [SettingsPage.self])
				final class AppSettings: SettingsPage, Instantiable {
				    init(feedBuilder: ErasedInstantiator<(), any FeedPage>?) {
				        self.feedBuilder = feedBuilder
				    }

				    @Received(onlyIfAvailable: true) private let feedBuilder: ErasedInstantiator<(), any FeedPage>?
				}

				\(caller)
				public final class Root: Instantiable {
				    public init(feedBuilder: ErasedInstantiator<(), any FeedPage>, signedInBuilder: Instantiator<SignedIn>) {
				        self.feedBuilder = feedBuilder
				        self.signedInBuilder = signedInBuilder
				    }

				    @Instantiated(fulfilledByType: "Feed") private let feedBuilder: ErasedInstantiator<(), any FeedPage>
				    @Instantiated private let signedInBuilder: Instantiator<SignedIn>
				}
				""",
			], dependencies: ["Feature"]),
		]
	}

	/// `w4ConstantCycleOptionalW4RemediedModules` with `Feed` and its initializer `public`, as its access errors’ fix-its make them.
	private static func w4ConstantCycleOptionalW4RemediedPublicFeedModules(caller: String, callee: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContentByFilePath: [
				"FeatureTypes.swift": """
				import SafeDI

				public protocol FeedPage {}

				public protocol SettingsPage {}

				public struct User {
				    public init(name: String) {
				        self.name = name
				    }

				    public let name: String
				}

				@Instantiable
				public final class Feed: FeedPage, Instantiable {
				    public init(user: User, settings: any SettingsPage) {
				        self.user = user
				        self.settings = settings
				    }

				    @Received private let user: User
				    @Received private let settings: any SettingsPage
				}

				\(callee)
				public final class SignedIn: Instantiable {
				    init(user: User, feedBuilder: ErasedInstantiator<(), any FeedPage>, settings: any SettingsPage) {
				        self.user = user
				        self.feedBuilder = feedBuilder
				        self.settings = settings
				    }

				    @Forwarded private let user: User
				    @Received private let feedBuilder: ErasedInstantiator<(), any FeedPage>
				    @Instantiated private let settings: any SettingsPage
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"AppTypes.swift": """
				import SafeDI
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [SettingsPage.self])
				final class AppSettings: SettingsPage, Instantiable {
				    init(feedBuilder: ErasedInstantiator<(), any FeedPage>?) {
				        self.feedBuilder = feedBuilder
				    }

				    @Received(onlyIfAvailable: true) private let feedBuilder: ErasedInstantiator<(), any FeedPage>?
				}

				\(caller)
				public final class Root: Instantiable {
				    public init(feedBuilder: ErasedInstantiator<(), any FeedPage>, signedInBuilder: Instantiator<SignedIn>) {
				        self.feedBuilder = feedBuilder
				        self.signedInBuilder = signedInBuilder
				    }

				    @Instantiated(fulfilledByType: "Feed") private let feedBuilder: ErasedInstantiator<(), any FeedPage>
				    @Instantiated private let signedInBuilder: Instantiator<SignedIn>
				}
				""",
			], dependencies: ["Feature"]),
		]
	}

	/// The called type built again, with its first remedy applied: `Home` receives `logger`.
	private static func seamBuiltAgainRemediedModules(caller: String, callee: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContentByFilePath: [
				"FeatureTypes.swift": """
				import SafeDI

				public protocol Api {}

				@Instantiable
				public final class Cache: Instantiable {
				    public init() {}
				}

				@Instantiable
				public final class Logger: Instantiable {
				    public init() {}
				}

				@Instantiable
				final class Loop: Instantiable {
				    init(logger: Logger, homeBuilder: Instantiator<Home>) {
				        self.logger = logger
				        self.homeBuilder = homeBuilder
				    }

				    @Instantiated private let logger: Logger
				    @Instantiated private let homeBuilder: Instantiator<Home>
				}

				\(callee)
				public final class Home: Instantiable {
				    init(logger: Logger, api: any Api, loopBuilder: Instantiator<Loop>) {
				        self.logger = logger
				        self.api = api
				        self.loopBuilder = loopBuilder
				    }

				    @Received private let logger: Logger
				    @Instantiated private let api: any Api
				    @Instantiated private let loopBuilder: Instantiator<Loop>
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"AppTypes.swift": """
				import SafeDI
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				final class LiveApi: Api, Instantiable {
				    init(logger: Logger) {
				        self.logger = logger
				    }

				    @Received private let logger: Logger
				}

				\(caller)
				public final class Root: Instantiable {
				    public init(logger: Logger, home: Home) {
				        self.logger = logger
				        self.home = home
				    }

				    @Instantiated private let logger: Logger
				    @Instantiated private let home: Home
				}
				""",
			], dependencies: ["Feature"]),
		]
	}

	/// The called type built again, with its second remedy applied: `Feature` declares a type that fulfills `Api`.
	private static func seamBuiltAgainFulfilledInFeatureModules(caller: String, callee: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContentByFilePath: [
				"FeatureTypes.swift": """
				import SafeDI

				public protocol Api {}

				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				public final class FeatureApi: Api, Instantiable {
				    public init(logger: Logger) {
				        self.logger = logger
				    }

				    @Received private let logger: Logger
				}

				@Instantiable
				public final class Cache: Instantiable {
				    public init() {}
				}

				@Instantiable
				public final class Logger: Instantiable {
				    public init() {}
				}

				@Instantiable
				final class Loop: Instantiable {
				    init(logger: Logger, homeBuilder: Instantiator<Home>) {
				        self.logger = logger
				        self.homeBuilder = homeBuilder
				    }

				    @Instantiated private let logger: Logger
				    @Instantiated private let homeBuilder: Instantiator<Home>
				}

				\(callee)
				public final class Home: Instantiable {
				    init(api: any Api, loopBuilder: Instantiator<Loop>) {
				        self.api = api
				        self.loopBuilder = loopBuilder
				    }

				    @Instantiated private let api: any Api
				    @Instantiated private let loopBuilder: Instantiator<Loop>
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"AppTypes.swift": """
				import SafeDI
				import Feature

				\(caller)
				public final class Root: Instantiable {
				    public init(logger: Logger, home: Home) {
				        self.logger = logger
				        self.home = home
				    }

				    @Instantiated private let logger: Logger
				    @Instantiated private let home: Home
				}
				""",
			], dependencies: ["Feature"]),
		]
	}

	/// A fill that receives `token`, which nothing in the calling tree builds (check 2b’s `implementationReceivesWhatNothingProvides`).
	private static func tokenModules(caller: String, callee: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "InnerModule", packageName: "InnerModule", swiftFileContentByFilePath: [
				"InnerModuleTypes.swift": """
				import SafeDI

				public protocol Api: AnyObject {}

				\(callee)
				public final class Inner: Instantiable {
				    init(api: any Api) { self.api = api }
				    @Instantiated public let api: any Api
				}
				""",
			]),
			ModuleFixture(name: "FeatureModule", packageName: "FeatureModule", swiftFileContentByFilePath: [
				"FeatureModuleTypes.swift": """
				import SafeDI
				import InnerModule

				@Instantiable
				public final class Database: Instantiable {
				    public init() {}
				}

				\(callee)
				public final class Feature: Instantiable {
				    init(database: Database, inner: Inner) { self.database = database; self.inner = inner }
				    @Instantiated public let database: Database
				    @Instantiated public let inner: Inner
				}
				""",
			], dependencies: ["InnerModule"]),
			ModuleFixture(name: "Tests", packageName: "Tests", swiftFileContentByFilePath: [
				"TestsTypes.swift": """
				import SafeDI
				import InnerModule
				import FeatureModule

				public struct Token {
				    public init() {}
				}

				@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
				final class Fake: Api, Instantiable {
				    init(token: Token) { self.token = token }
				    @Received let token: Token
				}

				\(caller)
				public final class Host: Instantiable {
				    public init(database: Database, inner: Inner) { self.database = database; self.inner = inner }
				    @Instantiated let database: Database
				    @Instantiated let inner: Inner
				}
				""",
			], dependencies: ["InnerModule", "FeatureModule"]),
		]
	}

	/// A fill that receives the caller’s own `database` (check 2b’s `callersOwnValue`).
	private static func ownValueModules(caller: String, callee: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "InnerModule", packageName: "InnerModule", swiftFileContentByFilePath: [
				"InnerModuleTypes.swift": """
				import SafeDI

				public protocol Api: AnyObject {}

				\(callee)
				public final class Inner: Instantiable {
				    init(api: any Api) { self.api = api }
				    @Instantiated public let api: any Api
				}
				""",
			]),
			ModuleFixture(name: "FeatureModule", packageName: "FeatureModule", swiftFileContentByFilePath: [
				"FeatureModuleTypes.swift": """
				import SafeDI
				import InnerModule

				@Instantiable
				public final class Database: Instantiable {
				    public init() {}
				}

				\(callee)
				public final class Feature: Instantiable {
				    init(database: Database, inner: Inner) { self.database = database; self.inner = inner }
				    @Instantiated public let database: Database
				    @Instantiated public let inner: Inner
				}
				""",
			], dependencies: ["InnerModule"]),
			ModuleFixture(name: "Tests", packageName: "Tests", swiftFileContentByFilePath: [
				"TestsTypes.swift": """
				import SafeDI
				import InnerModule
				import FeatureModule

				@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
				final class Fake: Api, Instantiable {
				    init(database: Database) { self.database = database }
				    @Received let database: Database
				}

				\(caller)
				public final class Host: Instantiable {
				    public init(database: Database, inner: Inner) { self.database = database; self.inner = inner }
				    @Instantiated let database: Database
				    @Instantiated let inner: Inner
				}
				""",
			], dependencies: ["InnerModule", "FeatureModule"]),
		]
	}

	/// W1’s accepted neighbour: the fill receives the `session` of `CheckoutScreen`, the inner called type (W1-c).
	private static func w1InnerValueModules(caller: String, callee: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Checkout", packageName: "Checkout", swiftFileContentByFilePath: [
				"CheckoutTypes.swift": """
				import SafeDI

				public protocol PaymentService {}

				@Instantiable
				public final class Session: Instantiable {
				    public init() {}
				}

				\(callee)
				public final class CheckoutScreen: Instantiable {
				    init(session: Session, payments: any PaymentService) {
				        self.session = session
				        self.payments = payments
				    }

				    @Instantiated private let session: Session
				    @Instantiated private let payments: any PaymentService
				}
				""",
			]),
			ModuleFixture(name: "Store", packageName: "Store", swiftFileContentByFilePath: [
				"StoreTypes.swift": """
				import SafeDI
				import Checkout

				@Instantiable
				public final class Cart: Instantiable {
				    public init() {}
				}

				\(callee)
				public final class StoreScreen: Instantiable {
				    init(cart: Cart, checkout: CheckoutScreen) {
				        self.cart = cart
				        self.checkout = checkout
				    }

				    @Instantiated private let cart: Cart
				    @Instantiated private let checkout: CheckoutScreen
				}
				""",
			], dependencies: ["Checkout"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"AppTypes.swift": """
				import SafeDI
				import Checkout
				import Store

				@Instantiable(fulfillingAdditionalTypes: [PaymentService.self])
				final class LivePaymentService: PaymentService, Instantiable {
				    init(session: Session) {
				        self.session = session
				    }

				    @Received private let session: Session
				}

				\(caller)
				public final class Root: Instantiable {
				    public init(store: StoreScreen) {
				        self.store = store
				    }

				    @Instantiated private let store: StoreScreen
				}
				""",
			], dependencies: ["Checkout", "Store"]),
		]
	}

	/// W4’s accepted neighbour: `AppSettings` receives the `user` `SignedIn` forwards (W4-b).
	private static func w4ForwardedValueModules(caller: String, callee: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContentByFilePath: [
				"FeatureTypes.swift": """
				import SafeDI

				public protocol FeedPage {}

				public protocol SettingsPage {}

				public struct User {
				    public init(name: String) {
				        self.name = name
				    }

				    public let name: String
				}

				@Instantiable
				final class Feed: FeedPage, Instantiable {
				    init(user: User, settingsBuilder: ErasedInstantiator<(), any SettingsPage>) {
				        self.user = user
				        self.settingsBuilder = settingsBuilder
				    }

				    @Received private let user: User
				    @Received private let settingsBuilder: ErasedInstantiator<(), any SettingsPage>
				}

				\(callee)
				public final class SignedIn: Instantiable {
				    init(user: User, feedBuilder: ErasedInstantiator<(), any FeedPage>, settingsBuilder: ErasedInstantiator<(), any SettingsPage>) {
				        self.user = user
				        self.feedBuilder = feedBuilder
				        self.settingsBuilder = settingsBuilder
				    }

				    @Forwarded private let user: User
				    @Instantiated(fulfilledByType: "Feed") private let feedBuilder: ErasedInstantiator<(), any FeedPage>
				    @Instantiated(fulfilledByType: "AppSettings") private let settingsBuilder: ErasedInstantiator<(), any SettingsPage>
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"AppTypes.swift": """
				import SafeDI
				import Feature

				@Instantiable
				final class AppSettings: SettingsPage, Instantiable {
				    init(user: User) {
				        self.user = user
				    }

				    @Received private let user: User
				}

				\(caller)
				public final class Root: Instantiable {
				    public init(signedInBuilder: Instantiator<SignedIn>) {
				        self.signedInBuilder = signedInBuilder
				    }

				    @Instantiated private let signedInBuilder: Instantiator<SignedIn>
				}
				""",
			], dependencies: ["Feature"]),
		]
	}

	/// A fill whose fulfiller, `GadgetSeam`, is a seam that passes its own hole up, and `StubGadget`, which no SafeDI declaration fulfills `Gadget` with (D3’s shape).
	private static func fulfilledBySeamModules(caller: String, callee: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Up", packageName: "Up", swiftFileContentByFilePath: [
				"UpTypes.swift": """
				import SafeDI

				public protocol Service: AnyObject {}
				public protocol Gadget: AnyObject {}

				\(callee)
				public final class Inner: Instantiable {
				    init(service: any Service) { self.service = service }
				    @Instantiated public let service: any Service
				}
				""",
			]),
			ModuleFixture(name: "Mid", packageName: "Mid", swiftFileContentByFilePath: [
				"MidTypes.swift": """
				import SafeDI
				import Up

				@Instantiable(generateDependencyTree: true, fulfillingAdditionalTypes: [Service.self])
				public final class GadgetSeam: Instantiable, Service {
				    init(gadget: any Gadget) { self.gadget = gadget }
				    @Instantiated public let gadget: any Gadget
				}

				public final class StubGadget: Gadget {
				    public init() {}
				}

				\(caller)
				public final class Feature: Instantiable {
				    public init(inner: Inner) { self.inner = inner }
				    @Instantiated public let inner: Inner
				}
				""",
			], dependencies: ["Up"]),
		]
	}
}

/// The kind of a calling mock: `generateMock: true` or `generateMock: .public`.
enum CallingMockCaller: CaseIterable, CustomTestStringConvertible {
	case `internal`
	case `public`

	/// The caller’s attribute line.
	var attribute: String {
		switch self {
		case .internal:
			"@Instantiable(generateMock: true)"
		case .public:
			"@Instantiable(generateMock: .public)"
		}
	}

	var testDescription: String {
		switch self {
		case .internal:
			"internal caller"
		case .public:
			"public caller"
		}
	}
}

/// How the types whose public mocks a calling mock calls are declared: seams as well as public mocks, or public mocks
/// only. The calling mock’s twin declares them seams either way.
enum CalledTypeDeclaration: CaseIterable, CustomTestStringConvertible {
	case seamAndPublicMock
	case publicMockOnly

	/// A called type’s attribute line.
	var attribute: String {
		switch self {
		case .seamAndPublicMock:
			"@Instantiable(generateDependencyTree: true, generateMock: .public)"
		case .publicMockOnly:
			"@Instantiable(generateMock: .public)"
		}
	}

	var testDescription: String {
		switch self {
		case .seamAndPublicMock:
			"called types are seams and public mocks"
		case .publicMockOnly:
			"called types are public mocks only"
		}
	}
}
