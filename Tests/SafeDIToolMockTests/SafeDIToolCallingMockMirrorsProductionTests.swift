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
			\(fixtures["App"]!["AppTypes.swift"]):12:5: error: `LivePaymentService` receives `cart: Cart`, which `OrderScreen` builds where it calls `CheckoutScreen`, but `OrderScreen` passes the builder for `CheckoutScreen`’s `payments: any PaymentService` (`payments` of `paymentServiceBuilder`) on from its own caller, which cannot hand it `OrderScreen`’s values. Declare `@Received let cart: Cart` on `CheckoutScreen`, so the builder’s values struct carries it, or declare an @Instantiable type that fulfills `PaymentService` in module `Order` or a module it lists among its SafeDI dependencies, so `OrderScreen` fills the builder itself.
			\(fixtures["Order"]!["OrderTypes.swift"]):16:5: note: `OrderScreen` declares `cart: Cart` here.
			"""
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.w1MiddleModuleModules(caller: caller.attribute, callee: calledTypes.attribute), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.w1MiddleModuleModules(caller: Self.twinCaller, callee: Self.twinCalledTypes), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: CallingMockCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsErrorOnOuterCalledTypesPath_whenMiddleTypeThatBuildsValueIsInOuterCalledTypesModule(caller: CallingMockCaller, calledTypes: CalledTypeDeclaration) async {
		// `OrderScreen` is in `StoreScreen`’s module, so `StoreScreen`’s public mock builds it inline, and the path where
		// `StoreScreen` calls `CheckoutScreen` is the one that loses `OrderScreen`’s `cart`. The twin builds `OrderScreen`
		// inline too: it declares it a plain type.
		let diagnostics = { (fixtures: [String: FixturePaths]) in
			"""
			\(fixtures["App"]!["AppTypes.swift"]):11:5: error: `LivePaymentService` receives `cart: Cart`, which `OrderScreen` builds on the path where `StoreScreen` calls `CheckoutScreen`, but `StoreScreen` passes the builder for `CheckoutScreen`’s `payments: any PaymentService` (`payments` of `paymentServiceBuilder`) on from its own caller, which cannot hand it that value. Declare `@Received let cart: Cart` on `CheckoutScreen`, so the builder’s values struct carries it, or declare an @Instantiable type that fulfills `PaymentService` in module `Store` or a module it lists among its SafeDI dependencies, so `StoreScreen` fills the builder itself.
			\(fixtures["Store"]!["StoreTypes.swift"]):16:5: note: `OrderScreen` declares `cart: Cart` here.
			"""
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.w1MiddleModules(caller: caller.attribute, callee: calledTypes.attribute, middle: calledTypes.attribute), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.w1MiddleModules(caller: Self.twinCaller, callee: Self.twinCalledTypes, middle: "@Instantiable"), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
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

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: CallingMockCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsEachHomesApiWithNearestLogger_whenCallingMocksFillReadsValueOfLevelBetweenBuildsOfCalledType(caller: CallingMockCaller, calledTypes: CalledTypeDeclaration) async throws {
		// The seam form passes the builder `Home` takes on unchanged where `Loop` builds `Home` again, so its caller cannot hand
		// the inner `Home`’s place `Loop`’s `logger`, and the twin reports it. The calling mock builds `Home` inline, so its
		// level functions hand that place `Loop`’s `logger` and the outer place `Root`’s, as inline does: it accepts the graph
		// and builds inline’s values, which the twin’s error would say of it falsely.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["AppTypes.swift"]):10:5: error: `LiveApi` receives `logger: Logger`, which `Home`’s tree builds where it instantiates `Home` again, but that call passes the builder `Home` takes for `Home`’s `api: any Api` on unchanged, so the caller that fills it cannot hand it those values. Declare `@Received let logger: Logger` on `Home`, so the builder’s values struct carries it, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies, so `Home` fills the builder itself.
			\(fixtures["Feature"]!["FeatureTypes.swift"]):22:5: note: `Loop` declares `logger: Logger` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.seamBuiltAgainModules(caller: Self.twinCaller, callee: Self.twinCalledTypes), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		try await expectValuesEqualInline(
			mock: Self.seamBuiltAgainModules(caller: caller.attribute, callee: calledTypes.attribute),
			inline: Self.seamBuiltAgainInlineModules,
			caller: caller,
			handWrittenCall: "import Feature\n\nfunc callMock() {\n    _ = Root.mock()\n}\n",
			probes: [DifferentialValueProbe(name: "Root", expression: "Root.mock()", knownRightExpression: "Root()")],
		)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: CallingMockCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsReenteredPlaceTheScreensCart_whenCallInsideFillReentersCalledTypesRootLevel(caller: CallingMockCaller, calledTypes: CalledTypeDeclaration) async throws {
		// `LivePayments` fills `Checkout`’s `payments` and builds `Checkout` again, from inside the fill of the `payments`
		// place `CartScreen` holds, where inline reads `CartScreen`’s `cart`. The call inside the fill re-enters the root level
		// function of the call that encloses it, and hands it its own `cart`, so the re-entered `Checkout`’s top place gets
		// `CartScreen`’s `cart`, as inline’s does, never the enclosing caller’s, which has none. The seam form passes the
		// builder on as module `App` fills it, whose scope there does not carry `cart`, so the twin reports it.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["AppTypes.swift"]):11:5: error: `LivePayments` receives `cart: Cart?`, which the builder for `CartScreen`’s `payments: any Payments` (`payments` of `paymentsBuilder`) carries from `CartScreen`, and that builder’s fill instantiates `Checkout` again (`retryBuilder`). Inline, `LivePayments` would read `CartScreen`’s `cart` inside that `Checkout`, but the call passes the builder on as module `App` fills it, whose scope there does not carry `cart`, so `LivePayments` would get `nil` or another value. Declare `@Received(onlyIfAvailable: true) let cart: Cart?` on `Checkout`, so the builder’s values struct carries it, or declare an @Instantiable type that fulfills `Payments` in module `Shared` or a module it lists among its SafeDI dependencies.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.reenteringFillModules(caller: Self.twinCaller, callee: Self.twinCalledTypes), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		try await expectValuesEqualInline(
			mock: Self.reenteringFillModules(caller: caller.attribute, callee: calledTypes.attribute),
			inline: Self.reenteringFillInlineModules,
			caller: caller,
			handWrittenCall: "import Shared\n\nfunc callMock() {\n    _ = Holder.mock()\n}\n",
			probes: [
				DifferentialValueProbe(name: "Holder", expression: "Holder.mock()", knownRightExpression: "Holder()"),
				DifferentialValueProbe(
					name: "retried payments’ cart",
					expression: "{ let cart = Cart(); let screen = Holder.mock().checkout.cartScreenBuilder.instantiate(cart); return ((screen.payments as! LivePayments).retryBuilder.instantiate().payments as! LivePayments).cart === cart }()",
					knownRightExpression: "{ let cart = Cart(); let screen = Holder().checkout.cartScreenBuilder.instantiate(cart); return ((screen.payments as! LivePayments).retryBuilder.instantiate().payments as! LivePayments).cart === cart }()",
				),
			],
			samples: [DifferentialValueSample(type: "Cart", expression: "Cart()")],
		)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsReenteredPlaceTheScreensCart_whenListedCallersCallInsideFillReentersCalledTypesRootLevel(calledTypes: CalledTypeDeclaration) async throws {
		// `Holder` has no `generateMock`: its module lists it in `additionalMocksToGenerate`, whose mock is internal. As for the
		// callers above, the call inside the fill hands the re-entered `Checkout`’s top place `CartScreen`’s `cart`.
		try await expectValuesEqualInline(
			mock: Self.reenteringFillModules(caller: "@Instantiable", callee: calledTypes.attribute, listsCaller: true),
			inline: Self.reenteringFillInlineModules,
			caller: .internal,
			handWrittenCall: "import Shared\n\nfunc callMock() {\n    _ = Holder.mock()\n}\n",
			probes: [
				DifferentialValueProbe(name: "Holder", expression: "Holder.mock()", knownRightExpression: "Holder()"),
				DifferentialValueProbe(
					name: "retried payments’ cart",
					expression: "{ let cart = Cart(); let screen = Holder.mock().checkout.cartScreenBuilder.instantiate(cart); return ((screen.payments as! LivePayments).retryBuilder.instantiate().payments as! LivePayments).cart === cart }()",
					knownRightExpression: "{ let cart = Cart(); let screen = Holder().checkout.cartScreenBuilder.instantiate(cart); return ((screen.payments as! LivePayments).retryBuilder.instantiate().payments as! LivePayments).cart === cart }()",
				),
			],
			samples: [DifferentialValueSample(type: "Cart", expression: "Cart()")],
		)
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

	@Test(arguments: CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTwinsCycle_whenFillOfListedMocksCallReceivesValueThatEnclosesTheCall(calledTypes: CalledTypeDeclaration) async {
		// `Root` has no `generateMock`: its module lists it in `additionalMocksToGenerate`. The fill of `SignedIn`’s `settings`
		// receives the `Session` whose tree calls `SignedIn`, which is still being built there.
		let diagnostics = { (fixtures: [String: FixturePaths]) in
			"""
			\(fixtures["App"]!["AppTypes.swift"]):10:5: error: Dependency cycle: `Session` -> `SignedIn` -> `any SettingsPage` -> `Session`. `AppSettings` receives `session: Session`, which is still being built when `AppSettings` is built. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
			\(fixtures["App"]!["AppTypes.swift"]):13:1: note: `Session` is part of the cycle
			\(fixtures["Feature"]!["FeatureTypes.swift"]):5:1: note: `SignedIn` is part of the cycle
			\(fixtures["App"]!["AppTypes.swift"]):4:1: note: `SettingsPage` is part of the cycle
			"""
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.listedMockCycleModules(caller: "@Instantiable", callee: calledTypes.attribute, listsCaller: true), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.listedMockCycleModules(caller: Self.twinCaller, callee: Self.twinCalledTypes, listsCaller: false), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTwinsHiddenReceiveError_whenFillOfListedMocksCallReceivesLabelDeclaredAgainAboveTheCall(calledTypes: CalledTypeDeclaration) async {
		// `Root` has no `generateMock`: its module lists it in `additionalMocksToGenerate`, so its mock is a mock root only
		// through that list. Inside the fill of `SignedIn`’s `settings`, the receive of `logger: Logger` is hidden by the
		// `logger: AuditLogger` that `Session`, which calls `SignedIn`, declares.
		let diagnostics = { (fixtures: [String: FixturePaths]) in
			"""
			\(fixtures["App"]!["AppTypes.swift"]):20:5: error: @Received property `logger: Logger` is hidden in chain: Root -> Session -> SignedIn -> AppSettings. `Session` declares `logger: AuditLogger` with the same label, so the types below `Session` receive `logger: AuditLogger` instead. Give `logger: AuditLogger` on `Session` a different label to fix.
			\(fixtures["App"]!["AppTypes.swift"]):30:5: note: `logger: AuditLogger` is declared here
			"""
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.listedMockHiddenModules(caller: "@Instantiable", callee: calledTypes.attribute, listsCaller: true), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.listedMockHiddenModules(caller: Self.twinCaller, callee: Self.twinCalledTypes, listsCaller: false), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
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

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: CallingMockCaller.allCases, CallerLazyValueForm.all)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceBelowCalledTypesRootWithCallersLazyValue_whenCalledMockHoldsValueByValue(caller: CallingMockCaller, form: CallerLazyValueForm) async throws {
		let (wrapper, place) = (form.wrapper, form.place)
		// `F`’s mock binds `log` by value, as the call hands it the caller’s instance, and its place is a level below its root,
		// beneath `A`. `Live` fills it and receives the caller’s lazily held `log`, so the place is filled on that route, as the
		// twin fills it, and `Live` holds the caller’s instance, as inline.
		try await expectValuesEqualInline(
			mock: Self.lazyValueBelowCalledRootModules(caller: caller.attribute, callee: Self.twinCalledTypes, wrapper: wrapper, place: place),
			inline: Self.lazyValueBelowCalledRootInlineModules(wrapper: wrapper, place: place),
			caller: caller,
			handWrittenCall: "import Feat\n\nfunc callMock() {\n    _ = Root.mock()\n}\n",
			probes: Self.lazyValueBelowCalledRootProbes(place: place),
		)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: CallerLazyWrapper.allCases, CalledMockPlace.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceBelowCalledTypesRootWithCallersLazyValue_whenListedCallersCalledMockHoldsValueByValue(wrapper: CallerLazyWrapper, place: CalledMockPlace) async throws {
		// As above, for a caller its module lists in `additionalMocksToGenerate`, whose mock is internal.
		try await expectValuesEqualInline(
			mock: Self.lazyValueBelowCalledRootModules(caller: "@Instantiable(isRoot: true)", callee: Self.twinCalledTypes, wrapper: wrapper, place: place, listsCaller: true),
			inline: Self.lazyValueBelowCalledRootInlineModules(wrapper: wrapper, place: place),
			caller: .internal,
			handWrittenCall: "import Feat\n\nfunc callMock() {\n    _ = Root.mock()\n}\n",
			probes: Self.lazyValueBelowCalledRootProbes(place: place),
		)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: CallingMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceBelowCalledTypesRootWithCallersLazyValue_whenCalledMockHoldsValueOnlyIfAvailable(caller: CallingMockCaller) async throws {
		// As above, with `Z` receiving `log` only if available, so `F`’s mock binds `log: Log?`, from which no level can make
		// the `LazilyInstantiated<Log>` `Live` requires: only the caller’s own wrapper fills the place, as the twin fills it.
		try await expectValuesEqualInline(
			mock: Self.lazyValueBelowCalledRootModules(caller: caller.attribute, callee: Self.twinCalledTypes, wrapper: .lazilyInstantiated, place: .plain, receivesOnlyIfAvailable: true),
			inline: Self.lazyValueBelowCalledRootInlineModules(wrapper: .lazilyInstantiated, place: .plain, receivesOnlyIfAvailable: true),
			caller: caller,
			handWrittenCall: "import Feat\n\nfunc callMock() {\n    _ = Root.mock()\n}\n",
			probes: Self.lazyValueBelowCalledRootProbes(place: .plain),
		)
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

	@Test(arguments: CallingMockCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTwinsError_whenFillInstantiatesTypeNoDeclarationCanFulfill(caller: CallingMockCaller, calledTypes: CalledTypeDeclaration) async {
		// `DefaultService`, which fills both of `Panel`’s places, instantiates a type spelled as no hole can be, which no
		// declaration fulfills: production reports it, so the calling mock reports the same error, in a build that compiles
		// the generated mocks.
		for (property, type) in [("names: [String]", "[String]"), ("lookup: [String: Int]", "[String: Int]"), ("make: () -> Int", "() -> Int"), ("pair: (Int, Int)", "(Int, Int)")] {
			let diagnostics = { (fixtures: [String: FixturePaths]) in
				"""
				\(fixtures["App"]!["AppTypes.swift"]):21:5: error: No @Instantiable type or extension fulfills `\(type)`, which @Instantiated property `\(property)` instantiates. Decorate `\(type)`, or an extension of it, with @Instantiable, or list `\(type)` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it.
				"""
			}
			await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
				try await executeSafeDIToolMultiModuleTest(modules: Self.fillInstantiatingGizmoModules(caller: caller.attribute, callee: calledTypes.attribute, defaultServiceProperties: [property], appActiveCompilationConditions: ["DEBUG"]), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
			}
			await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
				try await executeSafeDIToolMultiModuleTest(modules: Self.fillInstantiatingGizmoModules(caller: Self.twinCaller, callee: Self.twinCalledTypes, defaultServiceProperties: [property]), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
			}
		}
	}

	@Test(arguments: [MockConditionCaller.internal, .public, .listed])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesMockWithoutTwinsError_whenBuildLeavesMockConditionInactive(caller: MockConditionCaller) async throws {
		// The fill of the error above, in a release build: it compiles no generated mock, which is under `#if DEBUG`, so the
		// calling mock that cannot fill the place is never compiled, and the tool reports nothing.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.fillInstantiatingGizmoModules(
				caller: caller.attribute,
				callee: CalledTypeDeclaration.seamAndPublicMock.attribute,
				defaultServiceProperties: ["names: [String]"],
				listsScreen: caller == .listed,
				appIsReleaseConfiguration: true,
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)

		#expect(output.modules["App"]?.generatedFiles == caller.expectedReleaseFiles)
	}

	@Test(arguments: CallingMockCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_fillsAsTwin_whenTypeFillInstantiatesIsFulfilledAsTheErrorSuggests(caller: CallingMockCaller, calledTypes: CalledTypeDeclaration) async throws {
		// The remedy of the error above: an extension of `[String]` decorated with @Instantiable fulfills it, so the mock fills
		// both places with `DefaultService`, which builds `names` from the extension, as the twin does.
		let result = try await GraphFuzzerCallingMockCheck.run(Self.graph(
			named: "a fill whose fulfiller instantiates a type an extension fulfills",
			mock: Self.fillInstantiatingGizmoModules(caller: caller.attribute, callee: calledTypes.attribute, defaultServiceProperties: ["names: [String]"], appDeclarations: Self.stringArrayExtension),
			twin: Self.fillInstantiatingGizmoModules(caller: Self.twinCaller, callee: Self.twinCalledTypes, defaultServiceProperties: ["names: [String]"], appDeclarations: Self.stringArrayExtension),
			callerTypeName: "Screen",
			caller: caller,
			expectedTwinInitializerLabels: [],
			valueProbes: [DifferentialValueProbe(name: "Screen", expression: "App.Screen.mock()", knownRightExpression: "App.Screen()")],
		), seed: 0)

		Self.expectFillsAsTwin(result)
	}

	@Test(arguments: CallingMockCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_takesABuilderForWhatTheFillInstantiates_whenTwinDoes(caller: CallingMockCaller, calledTypes: CalledTypeDeclaration) async throws {
		// `Screen` fills both of `Panel`’s `service` places with `DefaultService`, whose `gizmo` nothing in `App` fulfills: the
		// twin fills them and takes `gizmoBuilder`, which each `DefaultService` calls once, so the mock does too.
		let result = try await GraphFuzzerCallingMockCheck.run(Self.graph(
			named: "a fill whose fulfiller instantiates a type nothing fulfills",
			mock: Self.fillInstantiatingGizmoModules(caller: caller.attribute, callee: calledTypes.attribute),
			twin: Self.fillInstantiatingGizmoModules(caller: Self.twinCaller, callee: Self.twinCalledTypes),
			callerTypeName: "Screen",
			caller: caller,
			implementationIsVisible: false,
			expectedPassUpLabels: ["gizmoBuilder"],
			expectedTwinInitializerLabels: nil,
			valueProbes: [DifferentialValueProbe(
				name: "Screen and the number of gizmoBuilder calls",
				expression: "{ () -> (App.Screen, Int) in var count = 0; let screen = App.Screen.mock(gizmoBuilder: { count += 1; return App.StubGizmo() }); return (screen, count) }()",
				knownRightExpression: "{ () -> (App.Screen, Int) in var count = 0; let screen = App.Screen(__safeDI_gizmoBuilder: .init(__safeDI_noScope: { count += 1; return App.StubGizmo() })); return (screen, count) }()",
			)],
		), seed: 0)

		Self.expectTakesTwinsBuilders(result, labels: ["gizmoBuilder"])
	}

	@Test(arguments: CallingMockCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_takesASendableBuilderForWhatTheFillInstantiates_whenPlaceIsBuiltInsideASendableFunction(caller: CallingMockCaller, calledTypes: CalledTypeDeclaration) async throws {
		// `DefaultService` holds `Part` in a `SendableInstantiator`, whose `@Sendable` builder function binds `gizmo`.
		let result = try await GraphFuzzerCallingMockCheck.run(Self.graph(
			named: "a fill whose fulfiller instantiates a type nothing fulfills inside a @Sendable function",
			mock: Self.fillInstantiatingGizmoModules(caller: caller.attribute, callee: calledTypes.attribute, defaultServiceProperties: ["part: SendableInstantiator<Part>"], appDeclarations: Self.part),
			twin: Self.fillInstantiatingGizmoModules(caller: Self.twinCaller, callee: Self.twinCalledTypes, defaultServiceProperties: ["part: SendableInstantiator<Part>"], appDeclarations: Self.part),
			callerTypeName: "Screen",
			caller: caller,
			implementationIsVisible: false,
			expectedPassUpLabels: ["gizmoSendableBuilder"],
			expectedTwinInitializerLabels: nil,
			valueProbes: [DifferentialValueProbe(
				name: "Screen",
				expression: "App.Screen.mock(gizmoSendableBuilder: { App.StubGizmo() })",
				knownRightExpression: "App.Screen(__safeDI_gizmoSendableBuilder: .init(__safeDI_noScope: { App.StubGizmo() }))",
			)],
		), seed: 0)

		Self.expectTakesTwinsBuilders(result, labels: ["gizmoSendableBuilder"])
	}

	@Test(arguments: CallingMockCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_takesTheWrappersBuilderForWhatTheFillInstantiates_whenPlaceIsAnErasedInstantiator(caller: CallingMockCaller, calledTypes: CalledTypeDeclaration) async throws {
		// `DefaultService` instantiates `makeGizmo: ErasedInstantiator<Int, any Gizmo>`, fulfilled by `DefaultGizmo`, which is
		// no `@Instantiable` type, so the builder forwards an `Int`.
		let declaration = "@Instantiated(fulfilledByType: \"DefaultGizmo\") public let makeGizmo: ErasedInstantiator<Int, any Gizmo>"
		let result = try await GraphFuzzerCallingMockCheck.run(Self.graph(
			named: "a fill whose fulfiller instantiates an erased instantiator nothing fulfills",
			mock: Self.fillInstantiatingGizmoModules(caller: caller.attribute, callee: calledTypes.attribute, defaultServiceProperties: [], defaultServiceDeclarations: [declaration], appDeclarations: Self.defaultGizmo),
			twin: Self.fillInstantiatingGizmoModules(caller: Self.twinCaller, callee: Self.twinCalledTypes, defaultServiceProperties: [], defaultServiceDeclarations: [declaration], appDeclarations: Self.defaultGizmo),
			callerTypeName: "Screen",
			caller: caller,
			implementationIsVisible: false,
			expectedPassUpLabels: ["defaultGizmo_GizmoBuilder"],
			expectedTwinInitializerLabels: nil,
			valueProbes: [DifferentialValueProbe(
				name: "Screen",
				expression: "App.Screen.mock(defaultGizmo_GizmoBuilder: { App.DefaultGizmo(id: $0) })",
				knownRightExpression: "App.Screen(__safeDI_defaultGizmo_GizmoBuilder: .init(__safeDI_noScope: { App.DefaultGizmo(id: $0) }))",
			)],
		), seed: 0)

		Self.expectTakesTwinsBuilders(result, labels: ["defaultGizmo_GizmoBuilder"])
	}

	@Test(arguments: CallingMockCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_takesABuilderForWhatTheFillInstantiates_whenFulfillersChildInstantiatesIt(caller: CallingMockCaller, calledTypes: CalledTypeDeclaration) async throws {
		// `DefaultService` instantiates `Part`, which instantiates `gizmo`, one level beneath the fulfiller.
		let result = try await GraphFuzzerCallingMockCheck.run(Self.graph(
			named: "a fill whose fulfiller’s child instantiates a type nothing fulfills",
			mock: Self.fillInstantiatingGizmoModules(caller: caller.attribute, callee: calledTypes.attribute, defaultServiceProperties: ["part: Part"], appDeclarations: Self.part),
			twin: Self.fillInstantiatingGizmoModules(caller: Self.twinCaller, callee: Self.twinCalledTypes, defaultServiceProperties: ["part: Part"], appDeclarations: Self.part),
			callerTypeName: "Screen",
			caller: caller,
			implementationIsVisible: false,
			expectedPassUpLabels: ["gizmoBuilder"],
			expectedTwinInitializerLabels: nil,
			valueProbes: [DifferentialValueProbe(name: "Screen", expression: "App.Screen.mock(gizmoBuilder: { App.StubGizmo() })", knownRightExpression: "App.Screen(__safeDI_gizmoBuilder: .init(__safeDI_noScope: { App.StubGizmo() }))")],
		), seed: 0)

		Self.expectTakesTwinsBuilders(result, labels: ["gizmoBuilder"])
	}

	@Test(arguments: CallingMockCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_takesOneBuilder_whenFillInstantiatesTwoPlacesOfOneHoleType(caller: CallingMockCaller, calledTypes: CalledTypeDeclaration) async throws {
		let result = try await GraphFuzzerCallingMockCheck.run(Self.graph(
			named: "a fill whose fulfiller instantiates two places of one hole type",
			mock: Self.fillInstantiatingGizmoModules(caller: caller.attribute, callee: calledTypes.attribute, defaultServiceProperties: ["first: any Gizmo", "second: any Gizmo"]),
			twin: Self.fillInstantiatingGizmoModules(caller: Self.twinCaller, callee: Self.twinCalledTypes, defaultServiceProperties: ["first: any Gizmo", "second: any Gizmo"]),
			callerTypeName: "Screen",
			caller: caller,
			implementationIsVisible: false,
			expectedPassUpLabels: ["gizmoBuilder"],
			expectedTwinInitializerLabels: nil,
			valueProbes: [DifferentialValueProbe(name: "Screen", expression: "App.Screen.mock(gizmoBuilder: { App.StubGizmo() })", knownRightExpression: "App.Screen(__safeDI_gizmoBuilder: .init(__safeDI_noScope: { App.StubGizmo() }))")],
		), seed: 0)

		Self.expectTakesTwinsBuilders(result, labels: ["gizmoBuilder"])
	}

	@Test(arguments: CallingMockCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_takesABuilderForEachHoleType_whenFillInstantiatesTwoHoleTypes(caller: CallingMockCaller, calledTypes: CalledTypeDeclaration) async throws {
		let result = try await GraphFuzzerCallingMockCheck.run(Self.graph(
			named: "a fill whose fulfiller instantiates two hole types",
			mock: Self.fillInstantiatingGizmoModules(caller: caller.attribute, callee: calledTypes.attribute, defaultServiceProperties: ["gizmo: any Gizmo", "widget: any Widget"]),
			twin: Self.fillInstantiatingGizmoModules(caller: Self.twinCaller, callee: Self.twinCalledTypes, defaultServiceProperties: ["gizmo: any Gizmo", "widget: any Widget"]),
			callerTypeName: "Screen",
			caller: caller,
			implementationIsVisible: false,
			expectedPassUpLabels: ["gizmoBuilder", "widgetBuilder"],
			expectedTwinInitializerLabels: nil,
			valueProbes: [DifferentialValueProbe(
				name: "Screen",
				expression: "App.Screen.mock(gizmoBuilder: { App.StubGizmo() }, widgetBuilder: { App.StubWidget() })",
				knownRightExpression: "App.Screen(__safeDI_gizmoBuilder: .init(__safeDI_noScope: { App.StubGizmo() }), __safeDI_widgetBuilder: .init(__safeDI_noScope: { App.StubWidget() }))",
			)],
		), seed: 0)

		Self.expectTakesTwinsBuilders(result, labels: ["gizmoBuilder", "widgetBuilder"])
	}

	@Test(arguments: CallingMockCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_callsTheBuilderByANameApart_whenFillDeclaresTheBuildersLabel(caller: CallingMockCaller, calledTypes: CalledTypeDeclaration) async throws {
		// `DefaultService` also instantiates `gizmoBuilder: GizmoFactory`, which would hide the builder `mock()` takes.
		let result = try await GraphFuzzerCallingMockCheck.run(Self.graph(
			named: "a fill that declares the builder’s label",
			mock: Self.fillInstantiatingGizmoModules(caller: caller.attribute, callee: calledTypes.attribute, defaultServiceProperties: ["gizmo: any Gizmo", "gizmoBuilder: GizmoFactory"], appDeclarations: Self.gizmoFactory),
			twin: Self.fillInstantiatingGizmoModules(caller: Self.twinCaller, callee: Self.twinCalledTypes, defaultServiceProperties: ["gizmo: any Gizmo", "gizmoBuilder: GizmoFactory"], appDeclarations: Self.gizmoFactory),
			callerTypeName: "Screen",
			caller: caller,
			implementationIsVisible: false,
			expectedPassUpLabels: ["gizmoBuilder"],
			expectedTwinInitializerLabels: nil,
			valueProbes: [DifferentialValueProbe(name: "Screen", expression: "App.Screen.mock(gizmoBuilder: { App.StubGizmo() })", knownRightExpression: "App.Screen(__safeDI_gizmoBuilder: .init(__safeDI_noScope: { App.StubGizmo() }))")],
		), seed: 0)

		Self.expectTakesTwinsBuilders(result, labels: ["gizmoBuilder"])
	}

	@Test(arguments: CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_takesABuilderForWhatTheFillInstantiates_whenInternalCallersOwnTreeAlsoInstantiatesIt(calledTypes: CalledTypeDeclaration) async throws {
		// `Screen` also instantiates `gizmo` outside every fill, which its internal mock takes as a flat parameter, as the
		// comment at `seamMockBuilders`’ call states; the fill’s places call the builder, as the twin’s do.
		let result = try await GraphFuzzerCallingMockCheck.run(Self.graph(
			named: "a fill whose fulfiller instantiates a type the caller instantiates too",
			mock: Self.fillInstantiatingGizmoModules(caller: CallingMockCaller.internal.attribute, callee: calledTypes.attribute, screenInstantiatesGizmo: true),
			twin: Self.fillInstantiatingGizmoModules(caller: Self.twinCaller, callee: Self.twinCalledTypes, screenInstantiatesGizmo: true),
			callerTypeName: "Screen",
			caller: .internal,
			flatParameterLabels: ["gizmo"],
			implementationIsVisible: false,
			expectedPassUpLabels: ["gizmoBuilder"],
			expectedTwinInitializerLabels: nil,
			valueProbes: [DifferentialValueProbe(name: "Screen", expression: "App.Screen.mock(gizmoBuilder: { App.StubGizmo() }, gizmo: App.StubGizmo())", knownRightExpression: "App.Screen(__safeDI_gizmoBuilder: .init(__safeDI_noScope: { App.StubGizmo() }))")],
		), seed: 0)

		Self.expectTakesTwinsBuilders(result, labels: ["gizmoBuilder"])
	}

	@Test(arguments: CallingMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTheValueTwoFillsReadInItsRequiredForm_whenTheirTypesAndTheCallerAreDeclaredInAnyOrder(caller: CallingMockCaller) async throws {
		// `DefaultService` receives `token: Token` and `DefaultGadget` `token: Token?` only if available, each beneath the
		// route where `Page` binds `token` and the one where nothing does: the call hands both fills the caller’s `token` in
		// its required form, which `mock()` takes, whatever order the three types are declared in.
		let declarations = [
			"""
			@Instantiable(fulfillingAdditionalTypes: [Service.self])
			public struct DefaultService: Service, Instantiable {
			    public init(token: Token) {
			        self.token = token
			    }

			    @Received public let token: Token
			}
			""",
			"""
			@Instantiable(fulfillingAdditionalTypes: [Gadget.self])
			public struct DefaultGadget: Gadget, Instantiable {
			    public init(token: Token?) {
			        self.token = token
			    }

			    @Received(onlyIfAvailable: true) public let token: Token?
			}
			""",
			"""
			\(caller.attribute)
			public struct HubScreen: Instantiable {
			    public init(hub: Hub) {
			        self.hub = hub
			    }

			    @Instantiated public let hub: Hub
			}
			""",
		]
		let orders = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
		var generatedFilesByOrder = [[Int]: [String: String]]()
		for order in orders {
			let modules = [
				Self.twoReadersCoreModule,
				ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
					"AppTypes.swift": "import Core\nimport SafeDI\n\n" + order.map { declarations[$0] }.joined(separator: "\n\n"),
				], dependencies: ["Core"]),
			]
			let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: order == orders[0] ? .returningOutcomeOnly : .skipped, filesToDelete: &filesToDelete)
			if order == orders[0], let compilation = output.compilation {
				#expect(compilation.failure == nil, "\(compilation.failure.map { "\($0)" } ?? "")")
			}
			generatedFilesByOrder[order] = output.modules["App"]?.generatedFiles
		}
		let firstFiles = try #require(generatedFilesByOrder[orders[0]])
		// The internal mock builds `token`, as inline does; the public one takes it, and builds it where its caller passes `nil`.
		let expectedSignature = switch caller {
		case .internal:
			"static func mock(\n        safeDIOverrides: SafeDIOverrides = .init()\n    ) -> HubScreen {"
		case .public:
			"static func mock(\n        token: Token? = nil,\n        safeDIOverrides: SafeDIOverrides = .init()\n    ) -> HubScreen {"
		}
		#expect(Self.mockSignature(of: "HubScreen", in: firstFiles["App.swift"] ?? "") == expectedSignature)
		for order in orders.dropFirst() {
			#expect(generatedFilesByOrder[order] == firstFiles, "order \(order)")
		}
	}

	@Test(arguments: CallingMockCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_handsEachRouteItsNearestTokenAsTwinDoes_whenOneRouteBindsTokenLazilyBesideCallersPlainToken(caller: CallingMockCaller, calledTypes: CalledTypeDeclaration) async throws {
		// `Desk` binds `token` lazily above one of `Model`’s places, and the caller holds a plain `token` above the other:
		// `DefaultService` reads `Desk`’s instance beneath `Desk` and the caller’s `token` beside it, as inline does. The twin
		// hands its fill `Desk`’s wrapper and a wrapper of the caller’s `token`; the mock builds what the twin builds.
		let result = try await GraphFuzzerCallingMockCheck.run(Self.graph(
			named: "a fill reading a token one route binds lazily and the caller holds by value",
			mock: Self.lazyRouteModules(caller: caller.attribute, callee: calledTypes.attribute),
			twin: Self.lazyRouteModules(caller: Self.twinCaller, callee: Self.twinCalledTypes),
			callerTypeName: "OfficeScreen",
			caller: caller,
			expectedTwinInitializerLabels: [],
			valueProbes: [DifferentialValueProbe(name: "OfficeScreen", expression: "App.OfficeScreen.mock()", knownRightExpression: "App.OfficeScreen()")],
		), seed: 0)

		Self.expectFillsAsTwin(result)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Office` builds `Model`, whose `service` is a place, inside `Desk`, which binds `token` lazily first, and beside it,
	/// where the caller’s plain `token` is nearest.
	private static func lazyRouteModules(caller: String, callee: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "Core", swiftFileContentByFilePath: ["CoreTypes.swift": lazyRouteCore(callee: callee)]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: ["AppTypes.swift": "import Core\n" + lazyRouteApp(caller: caller)], dependencies: ["Core"]),
		]
	}

	private static func lazyRouteCore(callee: String) -> String {
		"""
		import SafeDI

		public protocol Service {}

		@Instantiable
		public final class Token: Instantiable {
		    public init() {}
		}

		@Instantiable
		public struct Model: Instantiable {
		    public init(service: any Service) {
		        self.service = service
		    }

		    @Instantiated public let service: any Service
		}

		@Instantiable
		public struct Desk: Instantiable {
		    public init(token: LazilyInstantiated<Token>, model: Model) {
		        self.token = token
		        self.model = model
		    }

		    @Instantiated public let token: LazilyInstantiated<Token>
		    @Instantiated public let model: Model
		}

		\(callee)
		public struct Office: Instantiable {
		    init(desk: Desk, model: Model) {
		        self.desk = desk
		        self.model = model
		    }

		    @Instantiated public let desk: Desk
		    @Instantiated public let model: Model
		}
		"""
	}

	private static func lazyRouteApp(caller: String) -> String {
		"""
		import SafeDI

		@Instantiable(fulfillingAdditionalTypes: [Service.self])
		public struct DefaultService: Service, Instantiable {
		    public init(token: Token) {
		        self.token = token
		    }

		    @Received public let token: Token
		}

		\(caller)
		public struct OfficeScreen: Instantiable {
		    public init(token: Token, office: Office) {
		        self.token = token
		        self.office = office
		    }

		    @Instantiated public let token: Token
		    @Instantiated public let office: Office
		}
		"""
	}

	/// `Hub` builds `Model`, whose `service` and `gadget` are places, inside `Page`, which binds `token` first, and beside it.
	private static let twoReadersCoreModule = ModuleFixture(name: "Core", packageName: "Core", swiftFileContentByFilePath: [
		"CoreTypes.swift": """
		import SafeDI

		public protocol Service {}
		public protocol Gadget {}

		@Instantiable
		public final class Token: Instantiable {
		    public init() {}
		}

		@Instantiable
		public struct Model: Instantiable {
		    public init(service: any Service, gadget: any Gadget) {
		        self.service = service
		        self.gadget = gadget
		    }

		    @Instantiated public let service: any Service
		    @Instantiated public let gadget: any Gadget
		}

		@Instantiable
		public struct Page: Instantiable {
		    public init(token: Token, model: Model) {
		        self.token = token
		        self.model = model
		    }

		    @Instantiated public let token: Token
		    @Instantiated public let model: Model
		}

		@Instantiable(generateMock: .public)
		public struct Hub: Instantiable {
		    init(page: Page, model: Model) {
		        self.page = page
		        self.model = model
		    }

		    @Instantiated public let page: Page
		    @Instantiated public let model: Model
		}
		""",
	])

	/// The declaration of `typeName`’s `mock(` in `generatedFile`, from `static func mock(` or `public static func mock(`
	/// to the line that opens its body, or `nil` when the file declares none.
	private static func mockSignature(of typeName: String, in generatedFile: String) -> String? {
		guard let extensionRange = generatedFile.range(of: "extension \(typeName) {"),
		      let start = generatedFile.range(of: "static func mock(", range: extensionRange.upperBound..<generatedFile.endIndex),
		      let end = generatedFile.range(of: "-> \(typeName) {", range: start.upperBound..<generatedFile.endIndex)
		else { return nil }
		return String(generatedFile[start.lowerBound..<end.upperBound])
	}

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

	/// Expects `result`’s twin to have its graph’s intended outcome and the calling mock to take the builders `labels`, as the
	/// twin does, with no failure, and, where compile verification is on, the twin’s values.
	private static func expectTakesTwinsBuilders(_ result: GraphFuzzerCallingMockResult, labels: [String], sourceLocation: SourceLocation = #_sourceLocation) {
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")", sourceLocation: sourceLocation)
		#expect(result.passUps.map(\.label) == labels, sourceLocation: sourceLocation)
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

	/// Expects the calling mock of `mock` to be accepted and to compile with `handWrittenCall`, a call of its `mock()` in the
	/// caller’s module for an internal caller and in a module that depends on it for a `.public` one, and, where compile
	/// verification is on, `probes` to build in it what they build of `inline`, the same types in one module.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectValuesEqualInline(
		mock: [ModuleFixture],
		inline: [ModuleFixture],
		caller: CallingMockCaller,
		handWrittenCall: String,
		probes: [DifferentialValueProbe],
		samples: [DifferentialValueSample] = [],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
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
		guard compileVerificationIsEnabled, compilation.failure == nil else { return }
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inline, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		let comparison = try #require(try await DifferentialValueOracle.compare(
			feature: DifferentialValuePath(output: output, modules: modules),
			knownRight: DifferentialValuePath(output: inlineOutput, modules: inline),
			probes: probes,
			samples: samples,
			filesToDelete: &filesToDelete,
		), sourceLocation: sourceLocation)
		for difference in comparison.differences {
			Issue.record("The calling mock builds other values than inline for \(difference)\n\(comparison.report)", sourceLocation: sourceLocation)
		}
	}

	// MARK: Fixtures

	/// The adopter’s shape: `F`, a seam and public mock in module `Feat`, builds `A`, whose initializer `App` cannot call, so
	/// its place is a level below `F`’s root, and `Z`, which receives `log`, so `F`’s mock binds `log` by value. `Live` fills
	/// the place and receives `log` in `wrapper`’s form, which `Root` instantiates. Where `listsCaller`, module `App` lists
	/// `Root` in `additionalMocksToGenerate`.
	private static func lazyValueBelowCalledRootModules(caller: String, callee: String, wrapper: CallerLazyWrapper, place: CalledMockPlace, listsCaller: Bool = false, receivesOnlyIfAvailable: Bool = false) -> [ModuleFixture] {
		var appFiles = [
			"AppTypes.swift": """
			import Feat
			import SafeDI

			\(place.fill(receiving: "log: \(wrapper.name)<Log>"))

			\(caller)
			public final class Root: Instantiable {
			    public init(log: \(wrapper.name)<Log>, f: F) {
			        self.log = log
			        self.f = f
			    }

			    @Instantiated public let log: \(wrapper.name)<Log>
			    @Instantiated public let f: F
			}
			""",
		]
		if listsCaller {
			appFiles["SafeDIConfiguration.swift"] = "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Root\"])\n"
		}
		return [
			ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContentByFilePath: [
				"FeatTypes.swift": lazyValueBelowCalledRootFeatureTypes(callee: callee, place: place, receivesOnlyIfAvailable: receivesOnlyIfAvailable),
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: appFiles, dependencies: ["Feat"]),
		]
	}

	/// `lazyValueBelowCalledRootModules`’ types in one module, `Root` a root: what inline builds.
	private static func lazyValueBelowCalledRootInlineModules(wrapper: CallerLazyWrapper, place: CalledMockPlace, receivesOnlyIfAvailable: Bool = false) -> [ModuleFixture] {
		[
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"AppTypes.swift": lazyValueBelowCalledRootFeatureTypes(callee: "@Instantiable", place: place, receivesOnlyIfAvailable: receivesOnlyIfAvailable) + """


				\(place.fill(receiving: "log: \(wrapper.name)<Log>"))

				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(log: \(wrapper.name)<Log>, f: F) {
				        self.log = log
				        self.f = f
				    }

				    @Instantiated public let log: \(wrapper.name)<Log>
				    @Instantiated public let f: F
				}
				""",
			]),
		]
	}

	/// `Z` receives `log` only if available, as `Log?`, where `receivesOnlyIfAvailable`.
	private static func lazyValueBelowCalledRootFeatureTypes(callee: String, place: CalledMockPlace, receivesOnlyIfAvailable: Bool) -> String {
		let zLog = receivesOnlyIfAvailable ? "Log?" : "Log"
		let zReceive = receivesOnlyIfAvailable ? "@Received(onlyIfAvailable: true)" : "@Received"
		return """
		import SafeDI

		public protocol Api {}

		@Instantiable
		public final class Log: Instantiable, Sendable {
		    public init() {}
		}

		@Instantiable
		public final class A: Instantiable {
		    init(\(place.label): \(place.type)) {
		        self.\(place.label) = \(place.label)
		    }

		    \(place.attribute) public let \(place.label): \(place.type)
		}

		@Instantiable
		public final class Z: Instantiable {
		    init(log: \(zLog)) {
		        self.log = log
		    }

		    \(zReceive) public let log: \(zLog)
		}

		\(callee)
		public final class F: Instantiable {
		    public init(a: A, z: Z) {
		        self.a = a
		        self.z = z
		    }

		    @Instantiated public let a: A
		    @Instantiated public let z: Z
		}
		"""
	}

	/// What `Root`’s mock and inline `Root` build, and whether the `Live` that fills the place holds the instance `Root`’s
	/// `log` holds: for a deferred place, the `Live` its builder builds for `id` 7.
	private static func lazyValueBelowCalledRootProbes(place: CalledMockPlace) -> [DifferentialValueProbe] {
		let live = switch place {
		case .plain:
			"(root.f.a.api as! Live)"
		case .deferred:
			"(root.f.a.apiBuilder.instantiate(7) as! Live)"
		}
		return [
			DifferentialValueProbe(name: "Root", expression: "Root.mock()", knownRightExpression: "Root()"),
			DifferentialValueProbe(
				name: "Live’s log is Root’s",
				expression: "{ let root = Root.mock(); return \(live).log.instance === root.log.instance }()",
				knownRightExpression: "{ let root = Root(); return \(live).log.instance === root.log.instance }()",
			),
		]
	}

	/// `seamBuiltAgainModules`’ types in one module, `Root` a root: what inline builds.
	private static let seamBuiltAgainInlineModules = [
		ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
			"AppTypes.swift": """
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

			@Instantiable
			public final class Home: Instantiable {
			    init(api: any Api, loopBuilder: Instantiator<Loop>) {
			        self.api = api
			        self.loopBuilder = loopBuilder
			    }

			    @Instantiated private let api: any Api
			    @Instantiated private let loopBuilder: Instantiator<Loop>
			}

			@Instantiable(fulfillingAdditionalTypes: [Api.self])
			final class LiveApi: Api, Instantiable {
			    init(logger: Logger) {
			        self.logger = logger
			    }

			    @Received private let logger: Logger
			}

			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(logger: Logger, home: Home) {
			        self.logger = logger
			        self.home = home
			    }

			    @Instantiated private let logger: Logger
			    @Instantiated private let home: Home
			}
			""",
		]),
	]

	/// D1’s shape for a calling mock: `LivePayments` fills both of `Checkout`’s `payments` places, receives `cart` only if
	/// available, which only `CartScreen`, beneath the second place, holds, and builds `Checkout` again. Where `listsCaller`,
	/// module `App` lists `Holder` in `additionalMocksToGenerate`.
	private static func reenteringFillModules(caller: String, callee: String, listsCaller: Bool = false) -> [ModuleFixture] {
		var appFiles = [
			"AppTypes.swift": """
			import SafeDI
			import Shared

			@Instantiable(fulfillingAdditionalTypes: [(any Payments).self])
			public final class LivePayments: Payments, Instantiable {
			    public init(cart: Cart?, retryBuilder: Instantiator<Checkout>) {
			        self.cart = cart
			        self.retryBuilder = retryBuilder
			    }

			    @Received(onlyIfAvailable: true) public let cart: Cart?
			    @Instantiated public let retryBuilder: Instantiator<Checkout>
			}

			\(caller)
			public struct Holder: Instantiable {
			    public init(checkout: Checkout) {
			        self.checkout = checkout
			    }

			    @Instantiated public let checkout: Checkout
			}
			""",
		]
		if listsCaller {
			appFiles["SafeDIConfiguration.swift"] = "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Holder\"])\n"
		}
		return [
			ModuleFixture(name: "Shared", packageName: "Shared", swiftFileContentByFilePath: [
				"SharedTypes.swift": """
				import SafeDI

				public final class Cart {
				    public init() {}
				}

				public protocol Payments: AnyObject {}

				\(callee)
				public struct Checkout: Instantiable {
				    init(payments: any Payments, cartScreenBuilder: Instantiator<CartScreen>) {
				        self.payments = payments
				        self.cartScreenBuilder = cartScreenBuilder
				    }

				    @Instantiated public let payments: any Payments
				    @Instantiated public let cartScreenBuilder: Instantiator<CartScreen>
				}

				@Instantiable
				public struct CartScreen: Instantiable {
				    public init(cart: Cart, payments: any Payments) {
				        self.cart = cart
				        self.payments = payments
				    }

				    @Forwarded public let cart: Cart
				    @Instantiated public let payments: any Payments
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: appFiles, dependencies: ["Shared"]),
		]
	}

	/// `reenteringFillModules`’ types in one module, `Holder` a root: what inline builds.
	private static let reenteringFillInlineModules = [
		ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
			"AppTypes.swift": """
			import SafeDI

			public final class Cart {
			    public init() {}
			}

			public protocol Payments: AnyObject {}

			@Instantiable
			public struct Checkout: Instantiable {
			    init(payments: any Payments, cartScreenBuilder: Instantiator<CartScreen>) {
			        self.payments = payments
			        self.cartScreenBuilder = cartScreenBuilder
			    }

			    @Instantiated public let payments: any Payments
			    @Instantiated public let cartScreenBuilder: Instantiator<CartScreen>
			}

			@Instantiable
			public struct CartScreen: Instantiable {
			    public init(cart: Cart, payments: any Payments) {
			        self.cart = cart
			        self.payments = payments
			    }

			    @Forwarded public let cart: Cart
			    @Instantiated public let payments: any Payments
			}

			@Instantiable(fulfillingAdditionalTypes: [(any Payments).self])
			public final class LivePayments: Payments, Instantiable {
			    public init(cart: Cart?, retryBuilder: Instantiator<Checkout>) {
			        self.cart = cart
			        self.retryBuilder = retryBuilder
			    }

			    @Received(onlyIfAvailable: true) public let cart: Cart?
			    @Instantiated public let retryBuilder: Instantiator<Checkout>
			}

			@Instantiable(isRoot: true)
			public struct Holder: Instantiable {
			    public init(checkout: Checkout) {
			        self.checkout = checkout
			    }

			    @Instantiated public let checkout: Checkout
			}
			""",
		]),
	]

	/// W1:`LivePaymentService` fills `CheckoutScreen`’s place and receives the `cart` `StoreScreen`, which calls `CheckoutScreen`, builds (slice 4 helper’s W1-0).
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

	/// W1 three called types deep: the fill receives the `cart` of `OrderScreen`, the middle one (W1-h), in a module and
	/// package of its own between `StoreScreen`’s and `CheckoutScreen`’s.
	private static func w1MiddleModuleModules(caller: String, callee: String) -> [ModuleFixture] {
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
			ModuleFixture(name: "Order", packageName: "Order", swiftFileContentByFilePath: [
				"OrderTypes.swift": """
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
				""",
			], dependencies: ["Checkout"]),
			ModuleFixture(name: "Store", packageName: "Store", swiftFileContentByFilePath: [
				"StoreTypes.swift": """
				import SafeDI
				import Order

				\(callee)
				public final class StoreScreen: Instantiable {
				    init(order: OrderScreen) {
				        self.order = order
				    }

				    @Instantiated private let order: OrderScreen
				}
				""",
			], dependencies: ["Checkout", "Order"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"AppTypes.swift": """
				import SafeDI
				import Checkout
				import Order
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
			], dependencies: ["Checkout", "Order", "Store"]),
		]
	}

	/// W1-h with `OrderScreen` in `StoreScreen`’s module, declared with `middle`.
	private static func w1MiddleModules(caller: String, callee: String, middle: String) -> [ModuleFixture] {
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

				\(middle)
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

	/// A receive hidden inside a fill: `Root` builds `logger: Logger` and `Session`, which builds `logger: AuditLogger` and
	/// calls `SignedIn`, whose `settings` place `AppSettings` fills, receiving `logger: Logger`. Where `listsCaller`, module
	/// `App` lists `Root` in `additionalMocksToGenerate`.
	private static func listedMockCycleModules(caller: String, callee: String, listsCaller: Bool) -> [ModuleFixture] {
		var appFiles = [
			"AppTypes.swift": """
			import SafeDI
			import Feature

			@Instantiable(fulfillingAdditionalTypes: [SettingsPage.self])
			final class AppSettings: SettingsPage, Instantiable {
			    init(session: Session) {
			        self.session = session
			    }

			    @Received private let session: Session
			}

			@Instantiable
			final class Session: Instantiable {
			    init(signedIn: SignedIn) {
			        self.signedIn = signedIn
			    }

			    @Instantiated private let signedIn: SignedIn
			}

			\(caller)
			final class Root: Instantiable {
			    init(session: Session) {
			        self.session = session
			    }

			    @Instantiated private let session: Session
			}
			""",
		]
		if listsCaller {
			appFiles["SafeDIConfiguration.swift"] = "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Root\"])\n"
		}
		return [
			ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContentByFilePath: [
				"FeatureTypes.swift": """
				import SafeDI

				public protocol SettingsPage {}

				\(callee)
				public final class SignedIn: Instantiable {
				    init(settings: any SettingsPage) {
				        self.settings = settings
				    }

				    @Instantiated private let settings: any SettingsPage
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: appFiles, dependencies: ["Feature"]),
		]
	}

	private static func listedMockHiddenModules(caller: String, callee: String, listsCaller: Bool) -> [ModuleFixture] {
		var appFiles = [
			"AppTypes.swift": """
			import SafeDI
			import Feature

			@Instantiable
			final class Logger: Instantiable {
			    init() {}
			}

			@Instantiable
			final class AuditLogger: Instantiable {
			    init() {}
			}

			@Instantiable(fulfillingAdditionalTypes: [SettingsPage.self])
			final class AppSettings: SettingsPage, Instantiable {
			    init(logger: Logger) {
			        self.logger = logger
			    }

			    @Received private let logger: Logger
			}

			@Instantiable
			final class Session: Instantiable {
			    init(logger: AuditLogger, signedIn: SignedIn) {
			        self.logger = logger
			        self.signedIn = signedIn
			    }

			    @Instantiated private let logger: AuditLogger
			    @Instantiated private let signedIn: SignedIn
			}

			\(caller)
			final class Root: Instantiable {
			    init(logger: Logger, session: Session) {
			        self.logger = logger
			        self.session = session
			    }

			    @Instantiated private let logger: Logger
			    @Instantiated private let session: Session
			}
			""",
		]
		if listsCaller {
			appFiles["SafeDIConfiguration.swift"] = "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Root\"])\n"
		}
		return [
			ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContentByFilePath: [
				"FeatureTypes.swift": """
				import SafeDI

				public protocol SettingsPage {}

				\(callee)
				public final class SignedIn: Instantiable {
				    init(settings: any SettingsPage) {
				        self.settings = settings
				    }

				    @Instantiated private let settings: any SettingsPage
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: appFiles, dependencies: ["Feature"]),
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

	/// `Up`’s `Panel`, which builds a `Service` inside `Row` and one beside it, and `App`’s `Screen`, which calls `Panel` and
	/// fills both places with `DefaultService`, whose tree instantiates types no declaration `App` sees fulfills, by default
	/// `gizmo: any Gizmo`. `StubGizmo` and `StubWidget` are no SafeDI declarations. `listsScreen` lists `Screen` in `App`’s
	/// `additionalMocksToGenerate`; `App` is built with `appActiveCompilationConditions`, as a release build where
	/// `appIsReleaseConfiguration`.
	private static func fillInstantiatingGizmoModules(
		caller: String,
		callee: String,
		defaultServiceProperties: [String] = ["gizmo: any Gizmo"],
		defaultServiceDeclarations: [String] = [],
		appDeclarations: String = "",
		screenInstantiatesGizmo: Bool = false,
		listsScreen: Bool = false,
		appActiveCompilationConditions: [String] = [],
		appIsReleaseConfiguration: Bool = false,
	) -> [ModuleFixture] {
		let serviceDeclarations = defaultServiceProperties.map { "@Instantiated public let \($0)" } + defaultServiceDeclarations
		let serviceParameters = serviceDeclarations.compactMap { $0.components(separatedBy: " let ").last }
		let serviceLabels = serviceParameters.compactMap { $0.components(separatedBy: ":").first }
		let screenParameters = ["panel: Panel"] + (screenInstantiatesGizmo ? ["gizmo: any Gizmo"] : [])
		let screenLabels = screenParameters.compactMap { $0.components(separatedBy: ":").first }
		return [
			ModuleFixture(name: "Up", packageName: "Up", swiftFileContentByFilePath: [
				"UpTypes.swift": """
				import SafeDI

				public protocol Service: AnyObject {}

				@Instantiable
				public final class Row: Instantiable {
				    public init(service: any Service) { self.service = service }
				    @Instantiated public let service: any Service
				}

				\(callee)
				public final class Panel: Instantiable {
				    init(row: Row, service: any Service) {
				        self.row = row
				        self.service = service
				    }

				    @Instantiated public let row: Row
				    @Instantiated public let service: any Service
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"AppTypes.swift": """
				import SafeDI
				import Up

				public protocol Gizmo: AnyObject {}
				public protocol Widget: AnyObject {}

				public final class StubGizmo: Gizmo {
				    public init() {}
				}

				public final class StubWidget: Widget {
				    public init() {}
				}

				@Instantiable(fulfillingAdditionalTypes: [Service.self])
				public final class DefaultService: Instantiable, Service {
				    public init(\(serviceParameters.joined(separator: ", "))) {
				\(serviceLabels.map { "        self.\($0) = \($0)" }.joined(separator: "\n"))
				    }

				\(serviceDeclarations.map { "    \($0)" }.joined(separator: "\n"))
				}
				\(appDeclarations)
				\(caller)
				public final class Screen: Instantiable {
				    public init(\(screenParameters.joined(separator: ", "))) {
				\(screenLabels.map { "        self.\($0) = \($0)" }.joined(separator: "\n"))
				    }

				\(screenParameters.map { "    @Instantiated public let \($0)" }.joined(separator: "\n"))
				}
				""",
			].merging(listsScreen ? ["SafeDIConfiguration.swift": "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Screen\"])\n"] : [:]) { first, _ in first }, dependencies: ["Up"], activeCompilationConditions: appActiveCompilationConditions, isReleaseConfiguration: appIsReleaseConfiguration),
		]
	}

	/// A type that instantiates `gizmo`.
	private static let part = """

	@Instantiable
	public final class Part: Instantiable {
	    public init(gizmo: any Gizmo) { self.gizmo = gizmo }
	    @Instantiated public let gizmo: any Gizmo
	}

	"""

	/// The type an erased instantiator of `Gizmo` names, which is no SafeDI declaration.
	private static let defaultGizmo = """

	public final class DefaultGizmo: Gizmo {
	    public init(id: Int) {}
	}

	"""

	/// An extension that fulfills `[String]`, as the error for a type no declaration fulfills suggests.
	private static let stringArrayExtension = """

	@Instantiable
	extension [String]: Instantiable {
	    public static func instantiate() -> [String] {
	        ["name"]
	    }
	}

	"""

	/// A type a fill builds under the label of the builder `mock()` takes.
	private static let gizmoFactory = """

	@Instantiable
	public final class GizmoFactory: Instantiable {
	    public init() {}
	}

	"""

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

/// The kinds of caller whose generated mock the mock condition compiles out: an internal mock, a public mock, and a type
/// the module lists in `additionalMocksToGenerate`.
enum MockConditionCaller: CustomTestStringConvertible {
	case `internal`
	case `public`
	case listed

	/// The caller’s attribute line.
	var attribute: String {
		switch self {
		case .internal:
			CallingMockCaller.internal.attribute
		case .public:
			CallingMockCaller.public.attribute
		case .listed:
			"@Instantiable"
		}
	}

	var testDescription: String {
		switch self {
		case .internal:
			"internal caller"
		case .public:
			"public caller"
		case .listed:
			"listed caller"
		}
	}

	/// What a release build of `App` generates: the place passed up, which an internal mock and a listed type’s take as
	/// the same parameter.
	var expectedReleaseFiles: [String: String] {
		switch self {
		case .internal, .listed:
			["App.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif
			#if canImport(Up)
			import Up
			#endif

			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            panel: Panel.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                panel: panel
			            )
			        }

			        var panel: Panel.SafeDIOverrides { __safeDI_storage.panel }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                panel: Panel.SafeDIOverrides
			            ) {
			                self.panel = panel
			            }

			            let panel: Panel.SafeDIOverrides
			        }
			    }

			    static func mock(
			        serviceBuilder: @escaping () -> any Service,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let __safeDI_serviceBuilder = serviceBuilder
			        _ = Panel.__safeDI_Panel_mock_9A2B32943A6C59F5.self // If this line does not compile, compile the code SafeDI generates for module Up into Up: under Bazel, add Up’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			        func __safeDI_panel() -> Panel {
			            let serviceBuilder: () -> any Service = __safeDI_serviceBuilder
			            return Panel.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder), safeDIOverrides: safeDIOverrides.panel)
			        }
			        let panel: Panel = __safeDI_panel()
			        return Screen(panel: panel)
			    }
			}
			#endif
			"""]
		case .public:
			["App.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif
			#if canImport(Up)
			import Up
			#endif

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDIMockScope_Service {
			        nonisolated public struct panel_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let panel: (panel_Values) -> Panel.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>

			            public init(panel: @escaping (panel_Values) -> Panel.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>) {
			                self.panel = panel
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.panel = { _ in .init(__safeDI_noScope: __safeDI_builder) }
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            panel: Panel.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                panel: panel
			            )
			        }

			        public var panel: Panel.SafeDIOverrides { __safeDI_storage.panel }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                panel: Panel.SafeDIOverrides
			            ) {
			                self.panel = panel
			            }

			            let panel: Panel.SafeDIOverrides
			        }
			    }

			    public static func mock(
			        serviceBuilder: @escaping () -> any Service,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder), safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        serviceBuilder __safeDI_serviceBuilder: Screen.SafeDIMockScope_Service.__safeDI_Builder<any Service>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        _ = Panel.__safeDI_Panel_mock_9A2B32943A6C59F5.self // If this line does not compile, compile the code SafeDI generates for module Up into Up: under Bazel, add Up’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			        let panel = Panel.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.panel(SafeDIMockScope_Service.panel_Values()), safeDIOverrides: safeDIOverrides.panel)
			        return Screen(panel: panel)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_785941845E108814 {}
			}
			#endif
			"""]
		}
	}
}

/// The wrapper a calling mock’s caller holds a value in, which a fill receives.
enum CallerLazyWrapper: CaseIterable, CustomTestStringConvertible, Sendable {
	case lazilyInstantiated
	case sendableLazilyInstantiated

	var name: String {
		switch self {
		case .lazilyInstantiated:
			"LazilyInstantiated"
		case .sendableLazilyInstantiated:
			"SendableLazilyInstantiated"
		}
	}

	var testDescription: String {
		name
	}
}

/// A wrapper a calling mock’s caller holds a value in, and a place of the called public mock: each pair, for a test that
/// also varies the caller.
struct CallerLazyValueForm: CustomTestStringConvertible, Sendable {
	static let all = CallerLazyWrapper.allCases.flatMap { wrapper in CalledMockPlace.allCases.map { Self(wrapper: wrapper, place: $0) } }

	let wrapper: CallerLazyWrapper
	let place: CalledMockPlace

	var testDescription: String {
		"\(wrapper.testDescription), \(place.testDescription)"
	}
}

/// How a called public mock holds the place a calling mock fills: by value, as `any Api`, or as an `ErasedInstantiator`
/// whose fill forwards `id`.
enum CalledMockPlace: CaseIterable, CustomTestStringConvertible, Sendable {
	case plain
	case deferred

	var label: String {
		switch self {
		case .plain:
			"api"
		case .deferred:
			"apiBuilder"
		}
	}

	var type: String {
		switch self {
		case .plain:
			"any Api"
		case .deferred:
			"ErasedInstantiator<Int, any Api>"
		}
	}

	var attribute: String {
		switch self {
		case .plain:
			"@Instantiated"
		case .deferred:
			"@Instantiated(fulfilledByType: \"Live\")"
		}
	}

	/// `Live`, which fills the place and receives `received`, a label and its type.
	func fill(receiving received: String) -> String {
		let label = String(received.prefix { $0 != ":" })
		switch self {
		case .plain:
			return """
			@Instantiable(fulfillingAdditionalTypes: [Api.self])
			public final class Live: Api, Instantiable {
			    public init(\(received)) {
			        self.\(label) = \(label)
			    }

			    @Received public let \(received)
			}
			"""
		case .deferred:
			return """
			@Instantiable
			public final class Live: Api, Instantiable {
			    public init(id: Int, \(received)) {
			        self.id = id
			        self.\(label) = \(label)
			    }

			    @Forwarded public let id: Int
			    @Received public let \(received)
			}
			"""
		}
	}

	var testDescription: String {
		switch self {
		case .plain:
			"plain place"
		case .deferred:
			"deferred place"
		}
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
