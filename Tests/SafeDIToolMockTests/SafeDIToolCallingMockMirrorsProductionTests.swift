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
			\(fixtures["App"]!["AppTypes.swift"]):11:5: error: `LivePaymentService` receives `cart: Cart`, which `StoreScreen` builds where it calls `CheckoutScreen`, but `StoreScreen` passes the builder for `CheckoutScreen`’s `payments: any PaymentService` (`payments` of `paymentServiceBuilder`) on from its own caller, which cannot hand it `StoreScreen`’s values. Declare `@Received let cart: Cart` on `CheckoutScreen`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `PaymentService` in module `Store` or a module it lists among its SafeDI dependencies, so `StoreScreen` fills the builder itself.
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
			\(NormalizedFilePath(fixtures["App"]!.compilerPath(of: "AppTypes.swift")).path):11:5: error: `LivePaymentService` receives `cart: Cart`, which `StoreScreen` builds where it calls `CheckoutScreen`, but `StoreScreen` passes the builder for `CheckoutScreen`’s `payments: any PaymentService` (`payments` of `paymentServiceBuilder`) on from its own caller, which cannot hand it `StoreScreen`’s values. Declare `@Received let cart: Cart` on `CheckoutScreen`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `PaymentService` in module `Store` or a module it lists among its SafeDI dependencies, so `StoreScreen` fills the builder itself.
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
			\(fixtures["App"]!["AppTypes.swift"]):12:5: error: `LivePaymentService` receives `cart: Cart`, which `OrderScreen` builds where it calls `CheckoutScreen`, but `OrderScreen` passes the builder for `CheckoutScreen`’s `payments: any PaymentService` (`payments` of `paymentServiceBuilder`) on from its own caller, which cannot hand it `OrderScreen`’s values. Declare `@Received let cart: Cart` on `CheckoutScreen`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `PaymentService` in module `Order` or a module it lists among its SafeDI dependencies, so `OrderScreen` fills the builder itself.
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
			\(fixtures["App"]!["AppTypes.swift"]):11:5: error: `LivePaymentService` receives `cart: Cart`, which `OrderScreen` builds on the path where `StoreScreen` calls `CheckoutScreen`, but `StoreScreen` passes the builder for `CheckoutScreen`’s `payments: any PaymentService` (`payments` of `paymentServiceBuilder`) on from its own caller, which cannot hand it that value. Declare `@Received let cart: Cart` on `CheckoutScreen`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `PaymentService` in module `Store` or a module it lists among its SafeDI dependencies, so `StoreScreen` fills the builder itself.
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
			\(fixtures["App"]!["AppTypes.swift"]):11:5: error: `LivePaymentService` receives `cart: Cart?`, which `StoreScreen` builds where it calls `CheckoutScreen`, but `StoreScreen` passes the builder for `CheckoutScreen`’s `payments: any PaymentService` (`payments` of `paymentServiceBuilder`) on from its own caller, which cannot hand it `StoreScreen`’s values. Declare `@Received(onlyIfAvailable: true) let cart: Cart?` on `CheckoutScreen`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `PaymentService` in module `Store` or a module it lists among its SafeDI dependencies, so `StoreScreen` fills the builder itself.
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
			\(fixtures["App"]!["AppTypes.swift"]):11:5: error: `LivePaymentService` receives `cart: Cart`, which `Page` builds on the path where `StoreScreen` calls `CheckoutScreen`, but `StoreScreen` passes the builder for `CheckoutScreen`’s `payments: any PaymentService` (`payments` of `paymentServiceBuilder`) on from its own caller, which cannot hand it that value. Declare `@Received let cart: Cart` on `CheckoutScreen`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `PaymentService` in module `Store` or a module it lists among its SafeDI dependencies, so `StoreScreen` fills the builder itself.
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
			\(fixtures["App"]!["AppTypes.swift"]):10:5: error: `AppSettings` receives `feedBuilder: ErasedInstantiator<(), any FeedPage>`, which `SignedIn`’s tree builds only after it calls the builder for `SignedIn`’s `settingsBuilder: ErasedInstantiator<(), any SettingsPage>` (`settingsBuilder` of `appSettings_SettingsPageBuilder`), so SafeDI does not hand it to that builder. Declare `feedBuilder` and `settingsBuilder` on one type of module `App` instead, and have `SignedIn` instantiate a protocol that type fulfills in their place, so that type’s tree builds both, or declare an @Instantiable type that fulfills `AppSettings` in module `Feature` or a module it lists among its SafeDI dependencies.
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
		// `AppSettings` fills `SignedIn`’s `settings`, so receiving `feedBuilder` only if available would read a value
		// `SignedIn`’s tree binds after it calls that fill’s builder: the error states only the removal.
		let diagnostics = { (fixtures: [String: FixturePaths]) in
			"""
			\(fixtures["App"]!["AppTypes.swift"]):10:5: error: Dependency cycle: @Instantiated `feedBuilder: ErasedInstantiator<(), any FeedPage>` -> @Received `settings: any SettingsPage` -> @Received `feedBuilder: ErasedInstantiator<(), any FeedPage>`. `feedBuilder: ErasedInstantiator<(), any FeedPage>` is received while it is still being instantiated. Remove this @Received property.
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
			\(fixtures["App"]!["AppTypes.swift"]):10:5: error: `LiveApi` receives `logger: Logger`, which `Home`’s tree builds where it instantiates `Home` again, but that call passes the builder `Home` takes for `Home`’s `api: any Api` on unchanged, so the caller that fills it cannot hand it those values. Declare `@Received let logger: Logger` on `Home`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies, so `Home` fills the builder itself.
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
			\(fixtures["App"]!["AppTypes.swift"]):11:5: error: `LivePayments` receives `cart: Cart?`, which the builder for `CartScreen`’s `payments: any Payments` (`payments` of `paymentsBuilder`) carries from `CartScreen`, and that builder’s fill instantiates `Checkout` again (`retryBuilder`). Inline, `LivePayments` would read `CartScreen`’s `cart` inside that `Checkout`, but the call passes the builder on as module `App` fills it, whose scope there does not carry `cart`, so `LivePayments` would get `nil` or another value. Declare `@Received(onlyIfAvailable: true) let cart: Cart?` on `Checkout`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Payments` in module `Shared` or a module it lists among its SafeDI dependencies.
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

	@Test(arguments: CallingMockCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTwinsCycleStatingBothRemedies_whenCallingMocksFillReceivesBuilderItsCallerDeclares(caller: CallingMockCaller, calledTypes: CalledTypeDeclaration) async {
		// `LiveRouter` fills `SignedIn`’s `router` and receives the `aBuilder` that `Root`, not `SignedIn`’s tree, declares:
		// received only if available, the fill reads `Root`’s, as inline, so the error keeps both remedies.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: Self.callerDeclaredBuilderCycleDiagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.callerDeclaredBuilderCycleModules(caller: caller.attribute, callee: calledTypes.attribute), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: Self.callerDeclaredBuilderCycleDiagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.callerDeclaredBuilderCycleModules(caller: Self.twinCaller, callee: Self.twinCalledTypes), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTwinsCycleStatingBothRemedies_whenListedMocksFillReceivesBuilderItsCallerDeclares(calledTypes: CalledTypeDeclaration) async {
		// `Root` has no `generateMock`: its module lists it in `additionalMocksToGenerate`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: Self.callerDeclaredBuilderCycleDiagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.callerDeclaredBuilderCycleModules(caller: "@Instantiable", callee: calledTypes.attribute, listsCaller: true), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: Self.callerDeclaredBuilderCycleDiagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.callerDeclaredBuilderCycleModules(caller: Self.twinCaller, callee: Self.twinCalledTypes), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Tests – each error’s remedies work for the calling mock

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: CallingMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesCallingMockAndItsCall_whenInnerCalledTypeReceivesOuterValueAsW1ErrorSays(caller: CallingMockCaller) async throws {
		// The first remedy of the error `LivePaymentService`’s receive of `StoreScreen`’s `cart` gets: `CheckoutScreen`
		// receives `cart`, so SafeDI hands it to the builder.
		try await expectRemedyWorks(
			mock: Self.w1RemediedModules(caller: caller.attribute, callee: Self.twinCalledTypes),
			twin: Self.w1RemediedModules(caller: Self.twinCaller, callee: Self.twinCalledTypes),
			caller: caller,
			handWrittenCall: "import Checkout\nimport Store\n\nfunc callMock() {\n    _ = Root.mock()\n}\n",
		)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: CallingMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesCallingMockAndItsCall_whenOneAppTypeInstantiatesBothBuildersAsTheErrorSays(caller: CallingMockCaller) async throws {
		// The first remedy of W4’s error: `App`’s `LivePair` instantiates `feedBuilder` and `settingsBuilder`, and `SignedIn`
		// instantiates it in their place. `Feed`, which `LivePair` builds, and its initializer are `public`, as the access
		// errors’ fix-its make them.
		try await expectRemedyWorks(
			mock: Self.w4RestructuredModules(caller: caller.attribute, callee: Self.twinCalledTypes),
			twin: Self.w4RestructuredModules(caller: Self.twinCaller, callee: Self.twinCalledTypes),
			caller: caller,
			handWrittenCall: "import Feature\n\nfunc callMock() {\n    _ = Root.mock()\n}\n",
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

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: CallingMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesCallingMockAndItsCall_whenFillReceivesBuilderItsCallerDeclaresOnlyIfAvailableAsCycleErrorSays(caller: CallingMockCaller) async throws {
		// The second remedy of the dependency cycle where `Root` declares `aBuilder`: `LiveRouter` receives it only if available.
		try await expectRemedyWorks(
			mock: Self.callerDeclaredBuilderCycleModules(caller: caller.attribute, callee: Self.twinCalledTypes, receivesOnlyIfAvailable: true),
			twin: Self.callerDeclaredBuilderCycleModules(caller: Self.twinCaller, callee: Self.twinCalledTypes, receivesOnlyIfAvailable: true),
			caller: caller,
			handWrittenCall: "import Feature\n\nfunc callMock() {\n    _ = Root.mock()\n}\n",
		)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesListedMockAndItsCall_whenFillReceivesBuilderItsCallerDeclaresOnlyIfAvailableAsCycleErrorSays() async throws {
		// The same remedy where module `App` lists `Root` in `additionalMocksToGenerate`.
		try await expectRemedyWorks(
			mock: Self.callerDeclaredBuilderCycleModules(caller: "@Instantiable", callee: Self.twinCalledTypes, receivesOnlyIfAvailable: true, listsCaller: true),
			twin: Self.callerDeclaredBuilderCycleModules(caller: Self.twinCaller, callee: Self.twinCalledTypes, receivesOnlyIfAvailable: true),
			caller: .internal,
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
	mutating func generate_acceptsCallingMockAndTwin_whenCalledTypesModuleFulfillsSettingsAsTheErrorSays(caller: CallingMockCaller) async throws {
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
	mutating func generate_reachesAcceptedGraphWithTwinsValues_whenFillsOptionalReceiveIsFollowedThroughEachRemedy(caller: CallingMockCaller, calledTypes: CalledTypeDeclaration) async throws {
		// The plain W4 cycle with `feedBuilder` received only if available, which the cycle error does not state since it
		// leads to W4’s error, followed through every error it leads to: W4’s first remedy draws two access errors, whose
		// fix-its end in an accepted graph that builds what the twin builds. Each step’s text is the twin’s; the calling mock
		// reports the same at each step.

		// Step 1: `AppSettings` receives `feedBuilder` only if available.
		let w4Diagnostics = { (fixtures: [String: FixturePaths]) in
			"""
			\(fixtures["App"]!["AppTypes.swift"]):10:5: error: `AppSettings` receives `feedBuilder: ErasedInstantiator<(), any FeedPage>?`, which `SignedIn`’s tree builds only after it calls the builder for `SignedIn`’s `settings: any SettingsPage` (`settings` of `settingsPageBuilder`), so SafeDI does not hand it to that builder. Declare `feedBuilder` and `settings` on one type of module `App` instead, and have `SignedIn` instantiate a protocol that type fulfills in their place, so that type’s tree builds both, or declare an @Instantiable type that fulfills `SettingsPage` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["FeatureTypes.swift"]):35:5: note: `SignedIn` declares `feedBuilder: ErasedInstantiator<(), any FeedPage>` here.
			"""
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: w4Diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.w4ConstantCycleOptionalModules(caller: caller.attribute, callee: calledTypes.attribute), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: w4Diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.w4ConstantCycleOptionalModules(caller: Self.twinCaller, callee: Self.twinCalledTypes), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}

		// Step 2: `App`’s `LivePair` instantiates `feedBuilder` and `settings`, and `SignedIn` instantiates it in their place,
		// as W4’s error says. `Feed` and its initializer are `internal`, which the code built in `App` cannot reach; each
		// error’s fix-it makes them `public`. The calling mock, whose fill builds `Feed` as the twin’s does, reports the same
		// declarations in a build that tells the tool `DEBUG`, the mock condition.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["FeatureTypes.swift"]):16:1: error: `Feed` is `internal`, so the mock of `Root`, generated in module `App`, in another package, cannot construct it in the code SafeDI generates. Make `Feed` `public` to fix.
			\(fixtures["Feature"]!["FeatureTypes.swift"]):16:1-16:1: fixit: public\(" ")
			\(fixtures["Feature"]!["FeatureTypes.swift"]):17:5: error: `Feed`’s initializer is `internal`, so the mock of `Root`, generated in module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
			\(fixtures["Feature"]!["FeatureTypes.swift"]):17:5-17:5: fixit: public\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.w4ConstantCycleOptionalRestructuredModules(caller: caller.attribute, callee: calledTypes.attribute, feedIsPublic: false, appActiveCompilationConditions: ["DEBUG"]), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["FeatureTypes.swift"]):16:1: error: `Feed` is `internal`, so module `App`, in another package, cannot construct it in the code SafeDI generates. Make `Feed` `public` to fix.
			\(fixtures["Feature"]!["FeatureTypes.swift"]):16:1-16:1: fixit: public\(" ")
			\(fixtures["Feature"]!["FeatureTypes.swift"]):17:5: error: `Feed`’s initializer is `internal`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
			\(fixtures["Feature"]!["FeatureTypes.swift"]):17:5-17:5: fixit: public\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.w4ConstantCycleOptionalRestructuredModules(caller: Self.twinCaller, callee: Self.twinCalledTypes, feedIsPublic: false), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}

		// Step 3: the fix-its applied. `Feed` reads the `user` `SignedIn` forwards and the `settings` beside it in
		// `LivePair`, so neither the twin nor the mock takes anything.
		let result = try await GraphFuzzerCallingMockCheck.run(Self.graph(
			named: "the plain W4 cycle followed through each remedy",
			mock: Self.w4ConstantCycleOptionalRestructuredModules(caller: caller.attribute, callee: calledTypes.attribute, feedIsPublic: true),
			twin: Self.w4ConstantCycleOptionalRestructuredModules(caller: Self.twinCaller, callee: Self.twinCalledTypes, feedIsPublic: true),
			callerTypeName: "Root",
			caller: caller,
			flatParameterLabels: [],
			expectedTwinInitializerLabels: [],
			valueProbes: [DifferentialValueProbe(name: "Root", expression: "App.Root.mock()", knownRightExpression: "App.Root()")],
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

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: CallingMockCaller.allCases, CallerLazyWrapper.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceAtCalledTypesRootWithCallersLazyValue_whenCalledMockHoldsValueByValue(caller: CallingMockCaller, wrapper: CallerLazyWrapper) async throws {
		// As above, with the place on `F`’s root level, whose payload carries `F`’s copy of `log`: `Live` still holds the
		// caller’s wrapper, as inline.
		try await expectValuesEqualInline(
			mock: Self.lazyValueBelowCalledRootModules(caller: caller.attribute, callee: Self.twinCalledTypes, wrapper: wrapper, place: .plain, layout: .atRoot),
			inline: Self.lazyValueBelowCalledRootInlineModules(wrapper: wrapper, place: .plain, layout: .atRoot),
			caller: caller,
			handWrittenCall: "import Feat\n\nfunc callMock() {\n    _ = Root.mock()\n}\n",
			probes: Self.lazyValueBelowCalledRootProbes(place: .plain, layout: .atRoot),
		)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: CallingMockCallerKind.allCases, CallerLazyWrapper.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceAtCalledTypesRootWithCallersWrapperAndItsInstance_whenFillReadsBoth(caller: CallingMockCallerKind, wrapper: CallerLazyWrapper) async throws {
		// `F`’s place is on its root level, whose payload carries `F`’s by-value copy of `log`, and `Live`, which fills it, holds
		// `Root`’s wrapper while its child holds the instance. The copy provides only the instance, so the fill reads `Root`’s
		// `log`, which provides both: `Live` holds `Root`’s wrapper and its child the instance, as inline.
		try await expectValuesEqualInline(
			mock: Self.callersWrapperAndInstanceAtCalledRootModules(caller: caller, wrapper: wrapper),
			inline: Self.callersWrapperAndInstanceAtCalledRootInlineModules(wrapper: wrapper),
			caller: caller.callingMockCaller,
			handWrittenCall: "import Feat\n\nfunc callMock() {\n    _ = Root.mock()\n}\n",
			probes: Self.callersWrapperAndInstanceAtCalledRootProbes,
		)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: CallingMockCallerKind.allCases, MockRootBindingForm.all)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceWithWrapperMockBindsApartFromItsLabel_whenFillReadsWrapperCalledMocksCopyLacks(caller: CallingMockCallerKind, form: MockRootBindingForm) async throws {
		let (wrapper, shape) = (form.wrapper, form.shape)
		// `Mid`’s mock binds the wrapper `Live` reads under a name apart from `log`: beside the instance `mock()` takes as `log`,
		// beside another form of `log` it promotes, or beside a default-valued parameter of `mock()` labeled `log`. `F`’s mock
		// holds `log` by value, so the fill reads `Mid`’s wrapper under the name the mock binds it, as `Mid`’s mock built
		// inline reads it.
		try await expectValuesEqualInline(
			mock: Self.mockRootBindingModules(shape: shape, caller: caller, wrapper: wrapper),
			inline: Self.mockRootBindingInlineModules(shape: shape, caller: caller, wrapper: wrapper),
			caller: caller.callingMockCaller,
			handWrittenCall: "import Feat\n\nfunc callMock() {\n    _ = \(shape.mockCall(caller: caller.callingMockCaller, wrapper: wrapper))\n}\n",
			probes: Self.mockRootBindingProbes(shape: shape, mockCall: shape.mockCall(caller: caller.callingMockCaller, wrapper: wrapper)),
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillReadsWrapperUnderNameMockBindsIt_whenMockTakesInstanceOfWrapperMockedTypeReceives() async throws {
		// `Mid`’s mock takes `log: Log`, since nothing builds `Log`, and binds the `LazilyInstantiated<Log>` `Mid` receives as
		// `log_lazilyInstantiated`: the fill binds `log` to that wrapper, and no level function takes it.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.mockRootBindingModules(shape: .wrapperOfParameter, caller: .internal, wrapper: .lazilyInstantiated),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feat)
		import Feat
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Mid {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            f: F.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                f: f
		            )
		        }

		        var f: F.SafeDIOverrides { __safeDI_storage.f }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                f: F.SafeDIOverrides
		            ) {
		                self.f = f
		            }

		            let f: F.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        log: Log,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Mid {
		        let log_lazilyInstantiated = LazilyInstantiated<Log> { log }
		        func __safeDI_f() -> F {
		            func __safeDI_apiBuilder_F() -> F.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(a: { _ in __safeDI_apiBuilder_F_A_Scope() })
		            }
		            func __safeDI_apiBuilder_F_A_Scope() -> F.SafeDIMockScope_Api.A_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let log = log_lazilyInstantiated
		                    let api: any Api = Live(log: log)
		                    return api
		                })
		            }
		            _ = F.__safeDI_F_mock_A9AB1ED87D9AB450.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return F.__safeDI_mock(log: log, apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_F(), safeDIOverrides: safeDIOverrides.f)
		        }
		        let f: F = __safeDI_f()
		        return Mid(log: log_lazilyInstantiated, f: f)
		    }
		}
		#endif
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillReadsWrapperUnderNameMockBindsIt_whenMockPromotesLabelInTwoForms() async throws {
		// `Mid`’s mock builds `log` as the `LazilyInstantiated<Log>` `Live` receives and as the `Instantiator<Log>` `Other`
		// receives, each named apart: the fill binds `log` to the first.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.mockRootBindingModules(shape: .promotedBesideAnotherForm, caller: .internal, wrapper: .lazilyInstantiated),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feat)
		import Feat
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Mid {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            log_LazilyInstantiated__Log: (() -> Log)? = nil,
		            f: F.SafeDIOverrides = .init(),
		            log_Instantiator__Log: (() -> Log)? = nil,
		            other: ((Instantiator<Log>) -> Other)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                log_LazilyInstantiated__Log: log_LazilyInstantiated__Log,
		                f: f,
		                log_Instantiator__Log: log_Instantiator__Log,
		                other: other
		            )
		        }

		        var log_LazilyInstantiated__Log: (() -> Log)? { __safeDI_storage.log_LazilyInstantiated__Log }
		        var f: F.SafeDIOverrides { __safeDI_storage.f }
		        var log_Instantiator__Log: (() -> Log)? { __safeDI_storage.log_Instantiator__Log }
		        var other: ((Instantiator<Log>) -> Other)? { __safeDI_storage.other }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                log_LazilyInstantiated__Log: (() -> Log)?,
		                f: F.SafeDIOverrides,
		                log_Instantiator__Log: (() -> Log)?,
		                other: ((Instantiator<Log>) -> Other)?
		            ) {
		                self.log_LazilyInstantiated__Log = log_LazilyInstantiated__Log
		                self.f = f
		                self.log_Instantiator__Log = log_Instantiator__Log
		                self.other = other
		            }

		            let log_LazilyInstantiated__Log: (() -> Log)?
		            let f: F.SafeDIOverrides
		            let log_Instantiator__Log: (() -> Log)?
		            let other: ((Instantiator<Log>) -> Other)?
		        }
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Mid {
		        func __safeDI_log_LazilyInstantiated__Log() -> Log {
		            if let safeDIBuilder = safeDIOverrides.log_LazilyInstantiated__Log { safeDIBuilder() } else { Log() }
		        }
		        let log_LazilyInstantiated__Log = LazilyInstantiated<Log>(__safeDI_log_LazilyInstantiated__Log)
		        func __safeDI_f() -> F {
		            func __safeDI_apiBuilder_F() -> F.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(a: { _ in __safeDI_apiBuilder_F_A_Scope() })
		            }
		            func __safeDI_apiBuilder_F_A_Scope() -> F.SafeDIMockScope_Api.A_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let log = log_LazilyInstantiated__Log
		                    let api: any Api = Live(log: log)
		                    return api
		                })
		            }
		            _ = F.__safeDI_F_mock_96D996AD6269EFC2.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let log: LazilyInstantiated<Log> = log_LazilyInstantiated__Log
		            return F.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_F(), log: log.instance, safeDIOverrides: safeDIOverrides.f)
		        }
		        let f: F = __safeDI_f()
		        func __safeDI_log_Instantiator__Log() -> Log {
		            if let safeDIBuilder = safeDIOverrides.log_Instantiator__Log { safeDIBuilder() } else { Log() }
		        }
		        let log_Instantiator__Log = Instantiator<Log>(__safeDI_log_Instantiator__Log)
		        func __safeDI_other() -> Other {
		            let log: Instantiator<Log> = log_Instantiator__Log
		            return if let safeDIBuilder = safeDIOverrides.other { safeDIBuilder(log) } else { Other(log: log) }
		        }
		        let other: Other = __safeDI_other()
		        return Mid(f: f, other: other)
		    }
		}
		#endif
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillReadsWrapperUnderNameMockBindsIt_whenDefaultValuedParameterOfMockKeepsLabel() async throws {
		// `Mid`’s mock takes `log: String = ""`, its initializer’s default-valued parameter, under its label, and builds the
		// `LazilyInstantiated<Log>` `Live` receives as `log_Log`: the fill binds `log` to that wrapper.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.mockRootBindingModules(shape: .promotedBesideDefaultValuedParameter, caller: .internal, wrapper: .lazilyInstantiated),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feat)
		import Feat
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Mid {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            log_Log: (() -> Log)? = nil,
		            f: F.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                log_Log: log_Log,
		                f: f
		            )
		        }

		        var log_Log: (() -> Log)? { __safeDI_storage.log_Log }
		        var f: F.SafeDIOverrides { __safeDI_storage.f }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                log_Log: (() -> Log)?,
		                f: F.SafeDIOverrides
		            ) {
		                self.log_Log = log_Log
		                self.f = f
		            }

		            let log_Log: (() -> Log)?
		            let f: F.SafeDIOverrides
		        }
		    }

		    static func mock(
		        log: String = "",
		        apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Mid {
		        func __safeDI_log_Log() -> Log {
		            if let safeDIBuilder = safeDIOverrides.log_Log { safeDIBuilder() } else { Log() }
		        }
		        let log_Log = LazilyInstantiated<Log>(__safeDI_log_Log)
		        func __safeDI_f() -> F {
		            func __safeDI_apiBuilder_F() -> F.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(a: { _ in __safeDI_apiBuilder_F_A_Scope() })
		            }
		            func __safeDI_apiBuilder_F_A_Scope() -> F.SafeDIMockScope_Api.A_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let log = log_Log
		                    let api: any Api = Live(log: log)
		                    return api
		                })
		            }
		            _ = F.__safeDI_F_mock_96D996AD6269EFC2.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let log: LazilyInstantiated<Log> = log_Log
		            return F.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_F(), log: log.instance, safeDIOverrides: safeDIOverrides.f)
		        }
		        let f: F = __safeDI_f()
		        return Mid(f: f, log: log)
		    }
		}
		#endif
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillReadsCallersWrapper_whenFillOnCalledTypesRootLevelReadsWrapperAndItsInstance() async throws {
		// The payload of `F`’s root level carries `F`’s by-value copy of `log`, which provides only the instance `LiveChild`
		// reads: the fill binds nothing from the payload and reads `Root`’s `log`, its wrapper and its instance.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.callersWrapperAndInstanceAtCalledRootModules(caller: .internal, wrapper: .lazilyInstantiated),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feat)
		import Feat
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            log: (() -> Log)? = nil,
		            f: F.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                log: log,
		                f: f
		            )
		        }

		        var log: (() -> Log)? { __safeDI_storage.log }
		        var f: F.SafeDIOverrides { __safeDI_storage.f }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                log: (() -> Log)?,
		                f: F.SafeDIOverrides
		            ) {
		                self.log = log
		                self.f = f
		            }

		            let log: (() -> Log)?
		            let f: F.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_log() -> Log {
		            if let safeDIBuilder = safeDIOverrides.log { safeDIBuilder() } else { Log() }
		        }
		        let log = LazilyInstantiated<Log>(__safeDI_log)
		        func __safeDI_f() -> F {
		            func __safeDI_apiBuilder_F_api(_ scope: F.SafeDIMockScope_Api.api_Values) -> any Api {
		                func __safeDI_api() -> Live {
		                    let child = LiveChild(log: log.instance)
		                    return Live(log: log, child: child)
		                }
		                let api: any Api = __safeDI_api()
		                return api
		            }
		            func __safeDI_apiBuilder_F() -> F.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(api: { scope in __safeDI_apiBuilder_F_api(scope) })
		            }
		            _ = F.__safeDI_F_mock_7D841B2EEDD2A0BB.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return F.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_F(), log: log.instance, safeDIOverrides: safeDIOverrides.f)
		        }
		        let f: F = __safeDI_f()
		        return Root(log: log, f: f)
		    }
		}
		#endif
		""")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: CallingMockCaller.allCases, CallerLazyWrapper.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceBelowCalledTypesRootWithLevelsLazyValue_whenLevelDeclaresLabelAgain(caller: CallingMockCaller, wrapper: CallerLazyWrapper) async throws {
		// As above, with `B`, between `F` and `A`, instantiating a `log` of its own in the caller’s form, which hides `F`’s
		// copy and the caller’s beneath it: `Live` holds `B`’s wrapper, as inline, never the caller’s.
		try await expectValuesEqualInline(
			mock: Self.lazyValueBelowCalledRootModules(caller: caller.attribute, callee: Self.twinCalledTypes, wrapper: wrapper, place: .plain, layout: .redeclaredBelowRoot(wrapper)),
			inline: Self.lazyValueBelowCalledRootInlineModules(wrapper: wrapper, place: .plain, layout: .redeclaredBelowRoot(wrapper)),
			caller: caller,
			handWrittenCall: "import Feat\n\nfunc callMock() {\n    _ = Root.mock()\n}\n",
			probes: Self.lazyValueBelowCalledRootProbes(place: .plain, layout: .redeclaredBelowRoot(wrapper)),
		)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: [LazyValueLayout.atRoot, .redeclaredBelowRoot(.lazilyInstantiated)])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceAsInline_whenListedCallersCalledMockHoldsValueByValueBesidePlace(layout: LazyValueLayout) async throws {
		// The two tests above, for a caller its module lists in `additionalMocksToGenerate`, whose mock is internal.
		try await expectValuesEqualInline(
			mock: Self.lazyValueBelowCalledRootModules(caller: "@Instantiable(isRoot: true)", callee: Self.twinCalledTypes, wrapper: .lazilyInstantiated, place: .plain, listsCaller: true, layout: layout),
			inline: Self.lazyValueBelowCalledRootInlineModules(wrapper: .lazilyInstantiated, place: .plain, layout: layout),
			caller: .internal,
			handWrittenCall: "import Feat\n\nfunc callMock() {\n    _ = Root.mock()\n}\n",
			probes: Self.lazyValueBelowCalledRootProbes(place: .plain, layout: layout),
		)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceBelowCalledTypesRootWithCallersLazyValue_whenListedCallersCalledMockHoldsValueOnlyIfAvailable() async throws {
		// The `Log?` test above, for a caller its module lists in `additionalMocksToGenerate`, whose mock is internal.
		try await expectValuesEqualInline(
			mock: Self.lazyValueBelowCalledRootModules(caller: "@Instantiable(isRoot: true)", callee: Self.twinCalledTypes, wrapper: .lazilyInstantiated, place: .plain, listsCaller: true, receivesOnlyIfAvailable: true),
			inline: Self.lazyValueBelowCalledRootInlineModules(wrapper: .lazilyInstantiated, place: .plain, receivesOnlyIfAvailable: true),
			caller: .internal,
			handWrittenCall: "import Feat\n\nfunc callMock() {\n    _ = Root.mock()\n}\n",
			probes: Self.lazyValueBelowCalledRootProbes(place: .plain),
		)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: CallingMockCallerKind.allCases, CallerLazyWrapper.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceBelowCalledTypesRootWithMockedTypesLazyValue_whenMockedTypeBuildsCallBesideNothing(caller: CallingMockCallerKind, wrapper: CallerLazyWrapper) async throws {
		// `Mid`, between `Root`, which instantiates `log`, and `F`, builds `F` and declares nothing else, so `Mid.mock()` builds
		// the `log` its tree receives at its root, under the label. `Live` fills `F`’s place below its root and holds that
		// wrapper, whose instance `F`’s copy is, as inline `Live` holds `Root`’s.
		try await expectValuesEqualInline(
			mock: Self.lazyValueThroughMidModules(chain: .mockedMidBuildingCallBesideNothing, caller: caller, wrapper: wrapper),
			inline: Self.lazyValueThroughMidInlineModules(chain: .mockedMidBuildingCallBesideNothing, wrapper: wrapper),
			caller: caller.callingMockCaller,
			handWrittenCall: "import Feat\n\nfunc callMock() {\n    _ = Mid.mock()\n}\n",
			probes: Self.lazyValueThroughMidProbes(chain: .mockedMidBuildingCallBesideNothing),
		)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: CallingMockCallerKind.allCases, CallerLazyWrapper.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceBelowCalledTypesRootWithMockedTypesLazyValue_whenMockedTypeReceivesValue(caller: CallingMockCallerKind, wrapper: CallerLazyWrapper) async throws {
		// As above, with `Mid` receiving `log` itself: `Live` holds the wrapper `Mid` holds, as inline.
		try await expectValuesEqualInline(
			mock: Self.lazyValueThroughMidModules(chain: .mockedMidReceivingValue, caller: caller, wrapper: wrapper),
			inline: Self.lazyValueThroughMidInlineModules(chain: .mockedMidReceivingValue, wrapper: wrapper),
			caller: caller.callingMockCaller,
			handWrittenCall: "import Feat\n\nfunc callMock() {\n    _ = Mid.mock()\n}\n",
			probes: Self.lazyValueThroughMidProbes(chain: .mockedMidReceivingValue),
		)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: CallingMockCallerKind.allCases, [LazyValueChain.unmockedMid, .unmockedMidReceivingValueUnderAlias])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceBelowCalledTypesRootWithCallersLazyValue_whenTypeWithoutMockBuildsCall(caller: CallingMockCallerKind, chain: LazyValueChain) async throws {
		// `Root`’s mock is the calling mock, and `Mid`, which has no mock of its own, builds `F` between them, receiving
		// `Root`’s `log`, or `Root`’s `appLog` under an alias: `Live` holds `Root`’s wrapper, as inline.
		try await expectValuesEqualInline(
			mock: Self.lazyValueThroughMidModules(chain: chain, caller: caller, wrapper: .lazilyInstantiated),
			inline: Self.lazyValueThroughMidInlineModules(chain: chain, wrapper: .lazilyInstantiated),
			caller: caller.callingMockCaller,
			handWrittenCall: "import Feat\n\nfunc callMock() {\n    _ = Root.mock()\n}\n",
			probes: Self.lazyValueThroughMidProbes(chain: chain),
		)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: CallingMockCallerKind.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceBelowCalledTypesRootWithCallersLazyValue_whenCallIsInsideAnotherCallsFill(caller: CallingMockCallerKind) async throws {
		// `Root` calls `G`’s public mock, whose place `LiveG` fills, and `LiveG` builds `F`, whose place below its root `Live`
		// fills, reading `Root`’s `log`: `Live` holds `Root`’s wrapper, as inline.
		try await expectValuesEqualInline(
			mock: Self.callInsideFillModules(caller: caller),
			inline: Self.callInsideFillInlineModules,
			caller: caller.callingMockCaller,
			handWrittenCall: "import Feat\n\nfunc callMock() {\n    _ = Root.mock()\n}\n",
			probes: [
				DifferentialValueProbe(name: "Root", expression: "Root.mock()", knownRightExpression: "Root()"),
				DifferentialValueProbe(
					name: "Live’s log is Root’s",
					expression: "{ let root = Root.mock(); return ((root.g.ga.gapi as! LiveG).f.a.api as! Live).log === root.log }()",
					knownRightExpression: "{ let root = Root(); return ((root.g.ga.gapi as! LiveG).f.a.api as! Live).log === root.log }()",
				),
			],
		)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: CallingMockCallerKind.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlacesBelowCalledTypesRootWithCallersLazyValue_whenCalledTypeAlsoBuildsPlaceInSendableInstantiator(caller: CallingMockCallerKind) async throws {
		// `F` builds `A`’s place below its root in plain code and inside `aBuilder: SendableInstantiator<A>`, whose function
		// carries no field of the `log` `F`’s mock binds outside it: both `Live`s hold `Root`’s wrapper, as inline.
		try await expectValuesEqualInline(
			mock: Self.sendableInstantiatorPlaceModules(caller: caller),
			inline: Self.sendableInstantiatorPlaceInlineModules,
			caller: caller.callingMockCaller,
			handWrittenCall: "import Feat\n\nfunc callMock() {\n    _ = Root.mock()\n}\n",
			probes: [
				DifferentialValueProbe(name: "Root", expression: "Root.mock()", knownRightExpression: "Root()"),
				DifferentialValueProbe(
					name: "Live’s log is Root’s",
					expression: "{ let root = Root.mock(); return (root.f.a.api as! Live).log === root.log }()",
					knownRightExpression: "{ let root = Root(); return (root.f.a.api as! Live).log === root.log }()",
				),
				DifferentialValueProbe(
					name: "The instantiated Live’s log is Root’s",
					expression: "{ let root = Root.mock(); return (root.f.aBuilder.instantiate().api as! Live).log === root.log }()",
					knownRightExpression: "{ let root = Root(); return (root.f.aBuilder.instantiate().api as! Live).log === root.log }()",
				),
			],
		)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: CallingMockCallerKind.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlacesBelowCalledTypesRootWithCallersLazyValue_whenCalledTypeReceivingValueOnlyIfAvailableAlsoBuildsPlaceInSendableInstantiator(caller: CallingMockCallerKind) async throws {
		// As above, with `Z` receiving `log` only if available, so `F`’s mock binds `log: Log?`, which no place carries inside
		// the instantiator’s `@Sendable` function: both `Live`s hold `Root`’s wrapper, as inline.
		try await expectValuesEqualInline(
			mock: Self.sendableInstantiatorPlaceModules(caller: caller, receivesOnlyIfAvailable: true),
			inline: Self.sendableInstantiatorPlaceInlineModules(receivesOnlyIfAvailable: true),
			caller: caller.callingMockCaller,
			handWrittenCall: "import Feat\n\nfunc callMock() {\n    _ = Root.mock()\n}\n",
			probes: [
				DifferentialValueProbe(name: "Root", expression: "Root.mock()", knownRightExpression: "Root()"),
				DifferentialValueProbe(
					name: "Live’s log is Root’s",
					expression: "{ let root = Root.mock(); return (root.f.a.api as! Live).log === root.log }()",
					knownRightExpression: "{ let root = Root(); return (root.f.a.api as! Live).log === root.log }()",
				),
				DifferentialValueProbe(
					name: "The instantiated Live’s log is Root’s",
					expression: "{ let root = Root.mock(); return (root.f.aBuilder.instantiate().api as! Live).log === root.log }()",
					knownRightExpression: "{ let root = Root(); return (root.f.aBuilder.instantiate().api as! Live).log === root.log }()",
				),
			],
		)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: CallingMockCaller.allCases, ["Log", "LazilyInstantiated<Log>"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceInsideReenteringCallWithCallersValue_whenFillReceivingValueBuildsCalledTypeAgain(caller: CallingMockCaller, rootLog: String) async throws {
		// The adopter’s shape (`lazyValueBelowCalledRootModules`), with `Live` receiving `log: Log`, which `F`’s copy provides
		// on every level, and also building `F` again, so the call of `F`’s mock inside the fill re-enters the call’s root
		// level function; `Root` holds `log` by value or lazily. The fill reads nothing beside its place’s fields, so the
		// re-entered call’s place stays filled, and each `Live` holds the `log` nearest its call, as inline.
		try await expectValuesEqualInline(
			mock: Self.reenteringCallModules(caller: caller.attribute, rootLog: rootLog, fillLog: "Log", place: .plain),
			inline: Self.reenteringCallInlineModules(rootLog: rootLog, fillLog: "Log", place: .plain),
			caller: caller,
			handWrittenCall: "import Feat\n\nfunc callMock() {\n    _ = Root.mock()\n}\n",
			probes: Self.reenteringCallProbes(place: .plain, rootInstance: rootLog == "Log" ? "root.log" : "root.log.instance", fillInstance: "log"),
		)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: CallingMockCallerKind.allCases, ReenteredFunctionReadShape.all)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlacesWithCallersValue_whenFillBuildingCalledTypeAgainReadsLessOfValueThanReenteredFunctionTakes(caller: CallingMockCallerKind, shape: ReenteredFunctionReadShape) async throws {
		// `F` holds no `log`. `Live` fills its place `api`, below its root, receiving `Root`’s `log: Log`, so the call’s root
		// level function takes `log: Log`. `Live2` fills its place `api2` and builds `F` again, itself or through `G`’s public
		// mock, whose place `LiveG` fills by building `F`, so a call inside the fill re-enters that function, while `Live2`
		// reads `log` only if available, or not at all. The fill takes `log` as the re-entered function does
		// (`Scope.labelsHandedToReenteredFunctions(by:)`), and each `Live` and `Live2` holds `Root`’s `log`, as inline.
		try await expectValuesEqualInline(
			mock: Self.reenteredFunctionModules(caller: caller, shape: shape),
			inline: Self.reenteredFunctionInlineModules(shape: shape),
			caller: caller.callingMockCaller,
			handWrittenCall: "import Feat\n\nfunc callMock() {\n    _ = Root.mock()\n}\n",
			probes: Self.reenteredFunctionProbes(shape: shape),
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsReenteredFunctionCallersValue_whenFillBuildingCalledTypeAgainReadsValueOnlyIfAvailable() async throws {
		// The first shape of `generate_fillsPlacesWithCallersValue_whenFillBuildingCalledTypeAgainReadsLessOfValueThanReenteredFunctionTakes`:
		// `Live2` reads `log` only if available and builds `F` again itself, and `Root` holds `log: Log`. The fill of `api2`
		// takes `log: Log`, as `__safeDI_apiBuilder_F` and `__safeDI_api2Builder_F`, the root level functions its call
		// re-enters, do, and hands it on.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.reenteredFunctionModules(caller: .internal, shape: ReenteredFunctionReadShape(reentry: .direct, fillReadsLogOnlyIfAvailable: true, rootWrapper: nil)),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feat)
		import Feat
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            log: (() -> Log)? = nil,
		            f: F.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                log: log,
		                f: f
		            )
		        }

		        var log: (() -> Log)? { __safeDI_storage.log }
		        var f: F.SafeDIOverrides { __safeDI_storage.f }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                log: (() -> Log)?,
		                f: F.SafeDIOverrides
		            ) {
		                self.log = log
		                self.f = f
		            }

		            let log: (() -> Log)?
		            let f: F.SafeDIOverrides
		        }
		    }

		    static func mock(
		        api2Builder: (() -> any Api2)? = nil,
		        apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let log = if let safeDIBuilder = safeDIOverrides.log { safeDIBuilder() } else { Log() }
		        func __safeDI_f() -> F {
		            func __safeDI_api2Builder_F_B_Scope_api2(_ scope: F.SafeDIMockScope_Api2.B_Scope.api2_Values, log: Log) -> any Api2 {
		                func __safeDI_fillBody_A73A5FFDE1C9B538(log: Log) -> any Api2 {
		                    func __safeDI_api2() -> Live2 {
		                        func __safeDI_builder() -> F {
		                            F.__safeDI_mock(api2Builder: api2Builder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_api2Builder_F(log: log), apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_F(log: log))
		                        }
		                        let builder = Instantiator<F>(__safeDI_builder)
		                        return Live2(log: log, builder: builder)
		                    }
		                    let api2: any Api2 = __safeDI_api2()
		                    return api2
		                }
		                return __safeDI_fillBody_A73A5FFDE1C9B538(log: log)
		            }
		            func __safeDI_api2Builder_F(log: Log) -> F.SafeDIMockScope_Api2.__safeDI_Builder<any Api2> {
		                .init(b: { _ in __safeDI_api2Builder_F_B_Scope(log: log) })
		            }
		            func __safeDI_api2Builder_F_B_Scope(log: Log) -> F.SafeDIMockScope_Api2.B_Scope.__safeDI_Builder<any Api2> {
		                .init(api2: { scope in __safeDI_api2Builder_F_B_Scope_api2(scope, log: log) })
		            }
		            func __safeDI_apiBuilder_F(log: Log) -> F.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(a: { _ in __safeDI_apiBuilder_F_A_Scope(log: log) })
		            }
		            func __safeDI_apiBuilder_F_A_Scope(log: Log) -> F.SafeDIMockScope_Api.A_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = Live(log: log)
		                    return api
		                })
		            }
		            _ = F.__safeDI_F_mock_1F67931C545189ED.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return F.__safeDI_mock(api2Builder: api2Builder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_api2Builder_F(log: log), apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_F(log: log), safeDIOverrides: safeDIOverrides.f)
		        }
		        let f: F = __safeDI_f()
		        return Root(log: log, f: f)
		    }
		}
		#endif
		""")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: CallingMockCallerKind.allCases, [ReenteredFunctionReadShape.Reentry.direct, .throughChild, .throughOtherCall])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlacesWithCallersValue_whenFillBuildingCalledTypeAgainReadsNoneOfValueCallerHoldsByValue(caller: CallingMockCallerKind, reentry: ReenteredFunctionReadShape.Reentry) async throws {
		// The neighbour of `generate_passesBothPlacesUpWhole_whenFillBuildingCalledTypeAgainReadsNoneOfValueCallerHoldsLazily`
		// whose `Root` holds `log: Log`, which no declaration holds lazily: the fill that builds `F` again captures `Root`’s
		// `log`, which the re-entered function takes, so both places stay filled, and each `Live` holds `Root`’s `log`, as
		// inline.
		let shape = ReenteredFunctionReadShape(reentry: reentry, fillReadsLogOnlyIfAvailable: false, rootWrapper: nil)
		try await expectValuesEqualInline(
			mock: Self.reenteredFunctionModules(caller: caller, shape: shape),
			inline: Self.reenteredFunctionInlineModules(shape: shape),
			caller: caller.callingMockCaller,
			handWrittenCall: "import Feat\n\nfunc callMock() {\n    _ = Root.mock()\n}\n",
			probes: Self.reenteredFunctionProbes(shape: shape),
		)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: RedeclaredValueShape.all + RedeclaredValueShape.neighbours)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsReenteredFillsNearestDeclaration_whenFillBuildingCalledTypeAgainDeclaresValueAgain(shape: RedeclaredValueShape) async throws {
		// `F` holds a copy of `Root`’s `log` through `Z`. `Live` fills `api`, below `F`’s root, and reads `log`. `Live2` fills
		// `api2`, instantiates a `log` of its own and builds `F` again, which takes `Live2`’s `log` as its parameter: each
		// `Live` holds the `log` nearest it, `Root`’s and then `Live2`’s, in production (`Root()`) and in the mock, as inline,
		// since the level function of `api`’s level hands the fill the memo of the `F` it is part of
		// (`ScopeGenerator.FillDispatcher`’s `structDeclaration`).
		try await expectValuesEqualInline(
			mock: Self.redeclaredValueModules(shape: shape),
			inline: Self.redeclaredValueInlineModules(shape: shape),
			caller: .internal,
			handWrittenCall: "import Feat\n\nfunc callRoot() {\n    _ = Root()\n    _ = Root.mock()\n}\n",
			probes: Self.redeclaredValueProbes(shape: shape),
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsReenteredFillsLevelTheMemoOfTheCalledTypeBuiltAgain_whenFillBuildingCalledTypeAgainDeclaresValueAgain() async throws {
		// The primary shape of `generate_handsReenteredFillsNearestDeclaration_whenFillBuildingCalledTypeAgainDeclaresValueAgain`:
		// built again by the fill, a copy by value, `Root` holding `log` by value. The member of `api`’s level hands
		// `__safeDI_apiBuilder_F_A_Scope` the memo the struct of the `F` built there carries, `values.__safeDI_log`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.redeclaredValueModules(shape: RedeclaredValueShape(reentry: .direct, copyIsOptional: false, rootWrapper: nil)),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feat)
		import Feat
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_F() -> F.__safeDI_ApiCarrier<any Api> {
		            .init(a: { values_log, values_z in __safeDI_apiBuilder_F_A_Scope(log: values_log) })
		        }
		        func __safeDI_apiBuilder_F_A_Scope(log: LazilyInstantiated<Log>) -> F.__safeDI_ApiCarrier_A<any Api> {
		            .init(api: {
		                let api: any Api = Live(log: log.instance)
		                return api
		            })
		        }
		        let log = Log()
		        func __safeDI_f() -> F {
		            _ = F.__safeDI_F_6CCC739C88CBB5C8.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_api2Builder_F_B_Scope_api2() -> any Api2 {
		                func __safeDI_fillBody_81E0F8A25F8817B3() -> any Api2 {
		                    func __safeDI_api2() -> Live2 {
		                        let log = Log()
		                        func __safeDI_builder() -> F {
		                            _ = F.__safeDI_F_6CCC739C88CBB5C8.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                            return F(__safeDI_log: log, __safeDI_api2Builder: __safeDI_api2Builder_F(), __safeDI_apiBuilder: __safeDI_apiBuilder_F())
		                        }
		                        let builder = Instantiator<F>(__safeDI_builder)
		                        return Live2(log: log, builder: builder)
		                    }
		                    let api2: any Api2 = __safeDI_api2()
		                    return api2
		                }
		                return __safeDI_fillBody_81E0F8A25F8817B3()
		            }
		            func __safeDI_api2Builder_F() -> F.__safeDI_Api2Carrier<any Api2> {
		                .init(b: { values_log, values_z, values_a in __safeDI_api2Builder_F_B_Scope() })
		            }
		            func __safeDI_api2Builder_F_B_Scope() -> F.__safeDI_Api2Carrier_B<any Api2> {
		                .init(api2: { __safeDI_api2Builder_F_B_Scope_api2() })
		            }
		            return F(__safeDI_log: log, __safeDI_api2Builder: __safeDI_api2Builder_F(), __safeDI_apiBuilder: __safeDI_apiBuilder_F())
		        }
		        let f: F = __safeDI_f()
		        self.init(log: log, f: f)
		    }
		}

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            log: (() -> Log)? = nil,
		            f: F.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                log: log,
		                f: f
		            )
		        }

		        var log: (() -> Log)? { __safeDI_storage.log }
		        var f: F.SafeDIOverrides { __safeDI_storage.f }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                log: (() -> Log)?,
		                f: F.SafeDIOverrides
		            ) {
		                self.log = log
		                self.f = f
		            }

		            let log: (() -> Log)?
		            let f: F.SafeDIOverrides
		        }
		    }

		    static func mock(
		        api2Builder: (() -> any Api2)? = nil,
		        apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let log = if let safeDIBuilder = safeDIOverrides.log { safeDIBuilder() } else { Log() }
		        func __safeDI_f() -> F {
		            func __safeDI_api2Builder_F_B_Scope_api2(_ scope: F.SafeDIMockScope_Api2.B_Scope.api2_Values) -> any Api2 {
		                func __safeDI_fillBody_F5F0319C2F07108D() -> any Api2 {
		                    func __safeDI_api2() -> Live2 {
		                        let log = Log()
		                        func __safeDI_builder() -> F {
		                            F.__safeDI_mock(api2Builder: api2Builder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_api2Builder_F(), apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_F(), log: log)
		                        }
		                        let builder = Instantiator<F>(__safeDI_builder)
		                        return Live2(log: log, builder: builder)
		                    }
		                    let api2: any Api2 = __safeDI_api2()
		                    return api2
		                }
		                return __safeDI_fillBody_F5F0319C2F07108D()
		            }
		            func __safeDI_api2Builder_F() -> F.SafeDIMockScope_Api2.__safeDI_Builder<any Api2> {
		                .init(b: { _ in __safeDI_api2Builder_F_B_Scope() })
		            }
		            func __safeDI_api2Builder_F_B_Scope() -> F.SafeDIMockScope_Api2.B_Scope.__safeDI_Builder<any Api2> {
		                .init(api2: { scope in __safeDI_api2Builder_F_B_Scope_api2(scope) })
		            }
		            func __safeDI_apiBuilder_F() -> F.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(a: { values in __safeDI_apiBuilder_F_A_Scope(log: values.log) })
		            }
		            func __safeDI_apiBuilder_F_A_Scope(log: Log) -> F.SafeDIMockScope_Api.A_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = Live(log: log)
		                    return api
		                })
		            }
		            _ = F.__safeDI_F_mock_89EF74B0E3940DBA.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return F.__safeDI_mock(api2Builder: api2Builder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_api2Builder_F(), apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_F(), log: log, safeDIOverrides: safeDIOverrides.f)
		        }
		        let f: F = __safeDI_f()
		        return Root(log: log, f: f)
		    }
		}
		#endif
		""")
	}

	// MARK: Tests – a place passed up whole where a fill of a re-entered call reads the caller’s lazy value

	@Test(arguments: CallingMockCallerKind.allCases, ReenteredFunctionReadShape.passedUp)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesBothPlacesUpWhole_whenFillBuildingCalledTypeAgainReadsNoneOfValueCallerHoldsLazily(caller: CallingMockCallerKind, shape: ReenteredFunctionReadShape) async throws {
		// `F` holds no `log`. `Live` fills its place `api`, below its root, receiving `Root`’s `log` by value or only if
		// available, so the call’s root level function takes `log`. `Live2` fills its place `api2`, reads no `log`, and builds
		// `F` again, itself, through its child `Nav`, or through `G`’s public mock, whose place `LiveG` fills by building `F`.
		// `Root` holds `log` lazily, and the fill that builds `F` again would hand the re-entered function `Root`’s wrapper,
		// so `api` is passed up whole (`DependencyTreeGenerator.holeTypesTheFillGatesPassUp(of:in:lazilyHeldValues:)`), and
		// then `api2`, whose fill calls `F`’s mock, which now passes `api` up. Through `G`, filling both compiled, a stated
		// cost of the rule.
		let wrapper = try #require(shape.rootWrapper)
		try await expectPassesPlacesUpWhole(
			mock: Self.reenteredFunctionModules(caller: caller, shape: shape),
			caller: caller,
			wrapper: wrapper,
			builders: [.api2, .api],
			guards: PassedUpGuards(calledType: "1F67931C545189ED", root: "5D2B855AE809553B"),
			calledMockTakesLog: false,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesBothPlacesUpWhole_whenFillBuildingCalledTypeAgainReadsNoneOfValueCallerReceivesLazily() async throws {
		// The first shape of `generate_passesBothPlacesUpWhole_whenFillBuildingCalledTypeAgainReadsNoneOfValueCallerHoldsLazily`
		// in a feature module whose root lives in a module that depends on it: `Screen`, the calling mock, receives `log` as a
		// `LazilyInstantiated`, which no type of `App` instantiates and its mock builds. `api` and `api2` are passed up whole,
		// as there.
		let shape = ReenteredFunctionReadShape(reentry: .direct, fillReadsLogOnlyIfAvailable: false, rootWrapper: .lazilyInstantiated)
		var appTypes = Self.reenteredFunctionAppTypes(shape: shape, rootAttribute: "@Instantiable(isRoot: true)")
		appTypes = String(appTypes[..<(try #require(appTypes.range(of: "\n\n@Instantiable(isRoot: true)")).lowerBound)])
		appTypes += """


		@Instantiable(generateMock: true)
		public final class Screen: Instantiable {
		    public init(log: LazilyInstantiated<Log>, f: F) {
		        self.log = log
		        self.f = f
		    }

		    @Received public let log: LazilyInstantiated<Log>
		    @Instantiated public let f: F
		}
		"""
		let mock = [
			ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContentByFilePath: ["FeatTypes.swift": "import SafeDI\n\n" + Self.reenteredFunctionFeatureTypes(shape: shape, callee: Self.twinCalledTypes)]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: ["AppTypes.swift": "import Feat\nimport SafeDI\n\n" + appTypes], dependencies: ["Feat"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(mock, callingMockCaller: .internal, handWrittenCall: "import Feat\n\nfinal class StubApi: Api {}\nfinal class StubApi2: Api2 {}\n\nfunc callMock() {\n    _ = Screen.mock(api2Builder: { StubApi2() }, apiBuilder: { StubApi() })\n}\n"),
			integration: .moduleInfo,
			compileVerification: .returningOutcomeOnly,
			filesToDelete: &filesToDelete,
		)
		if compileVerificationIsEnabled {
			let compilation = try #require(output.compilation)
			#expect(compilation.failure == nil, "\(compilation.failure.map { "\($0)" } ?? "")")
		}
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feat)
		import Feat
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            f: F.SafeDIOverrides = .init(),
		            log: (() -> Log)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                f: f,
		                log: log
		            )
		        }

		        var f: F.SafeDIOverrides { __safeDI_storage.f }
		        var log: (() -> Log)? { __safeDI_storage.log }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                f: F.SafeDIOverrides,
		                log: (() -> Log)?
		            ) {
		                self.f = f
		                self.log = log
		            }

		            let f: F.SafeDIOverrides
		            let log: (() -> Log)?
		        }
		    }

		    static func mock(
		        api2Builder: @escaping () -> any Api2,
		        apiBuilder: @escaping () -> any Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let __safeDI_api2Builder = api2Builder
		        let __safeDI_apiBuilder = apiBuilder
		        _ = F.__safeDI_F_mock_1F67931C545189ED.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        func __safeDI_f() -> F {
		            let api2Builder: () -> any Api2 = __safeDI_api2Builder
		            let apiBuilder: () -> any Api = __safeDI_apiBuilder
		            return F.__safeDI_mock(api2Builder: .init(__safeDI_noScope: api2Builder), apiBuilder: .init(__safeDI_noScope: apiBuilder), safeDIOverrides: safeDIOverrides.f)
		        }
		        let f: F = __safeDI_f()
		        func __safeDI_log() -> Log {
		            if let safeDIBuilder = safeDIOverrides.log { safeDIBuilder() } else { Log() }
		        }
		        let log = LazilyInstantiated<Log>(__safeDI_log)
		        return Screen(log: log, f: f)
		    }
		}
		#endif
		""")
	}

	@Test(arguments: CallingMockCallerKind.allCases, CallerLazyWrapper.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesPlaceUpWhole_whenFillReadingCallersLazyValueBuildsCalledTypeAgain(caller: CallingMockCallerKind, wrapper: CallerLazyWrapper) async throws {
		// The adopter’s shape (`lazyValueBelowCalledRootModules`), with `Live` also building `F` again, so `F` is re-entered,
		// and `Live` reads `Root`’s wrapper beside its place’s fields: `Root`’s mock passes `api` up whole, as the twin’s
		// fill could not be mirrored there (`DependencyTreeGenerator.holeTypesTheFillGatesPassUp(of:in:lazilyHeldValues:)`).
		try await expectPassesPlacesUpWhole(
			mock: Self.reenteringCallModules(caller: caller.attribute(listed: "@Instantiable(isRoot: true)"), rootLog: "\(wrapper.name)<Log>", fillLog: "\(wrapper.name)<Log>", place: .plain, listsCaller: caller == .listed),
			caller: caller,
			wrapper: wrapper,
			builders: [.api],
			guards: PassedUpGuards(calledType: "96D996AD6269EFC2", root: "40C8AF0D9D958F7B"),
		)
	}

	@Test(arguments: CallingMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesPlaceUpWhole_whenFillDeclaresCallersLazyValueAgainAboveCallThatBuildsCalledTypeAgain(caller: CallingMockCaller) async throws {
		// As above, with `Live` building `M`, which instantiates a `log` of its own and builds `F` again: `Live` still reads
		// `Root`’s wrapper beside its place’s fields, so `api` is passed up whole, and `Root`’s mock is the one above.
		try await expectPassesPlacesUpWhole(
			mock: Self.reenteringCallModules(caller: caller.attribute, rootLog: "LazilyInstantiated<Log>", fillLog: "LazilyInstantiated<Log>", place: .plain, redeclaredAboveCall: true),
			caller: caller == .internal ? .internal : .public,
			wrapper: .lazilyInstantiated,
			builders: [.api],
			guards: PassedUpGuards(calledType: "96D996AD6269EFC2", root: "40C8AF0D9D958F7B"),
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesDeferredPlaceUpWhole_whenFillReadingCallersLazyValueBuildsCalledTypeAgain() async throws {
		// The first test above, with `A` holding the place as an `ErasedInstantiator<Int, any Api>` whose fill forwards `id`:
		// `Root`’s mock takes the instantiator’s builder.
		try await expectPassesPlacesUpWhole(
			mock: Self.reenteringCallModules(caller: CallingMockCaller.internal.attribute, rootLog: "LazilyInstantiated<Log>", fillLog: "LazilyInstantiated<Log>", place: .deferred),
			caller: .internal,
			wrapper: .lazilyInstantiated,
			builders: [.liveApi],
			guards: PassedUpGuards(calledType: "DA30F3B18913E099", root: nil),
		)
	}

	@Test(arguments: CallingMockCaller.allCases, CallerLazyValueForm.all)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesPlaceOnCalledTypesRootUpWhole_whenFillReadingCallersLazyValueBuildsCalledTypeAgain(caller: CallingMockCaller, form: CallerLazyValueForm) async throws {
		let (wrapper, place) = (form.wrapper, form.place)
		// The first test above, with the place on `F`’s own level, whose payload carries `F`’s by-value copy of `log`: `api`
		// is passed up whole.
		var builders = [PassedUpBuilder.api]
		var guards = PassedUpGuards(calledType: "7D841B2EEDD2A0BB", root: "0C12B745593904E0")
		if place == .deferred {
			builders = [.liveApi]
			guards = PassedUpGuards(calledType: "C7F36A0930131814", root: "DA4EF50B12AB0A74")
		}
		try await expectPassesPlacesUpWhole(
			mock: Self.reenteringCallModules(caller: caller.attribute, rootLog: "\(wrapper.name)<Log>", fillLog: "\(wrapper.name)<Log>", place: place, layout: .atRoot),
			caller: caller == .internal ? .internal : .public,
			wrapper: wrapper,
			builders: builders,
			guards: guards,
		)
	}

	@Test(arguments: CallingMockCallerKind.allCases, ReenteringWrapperPair.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesBothPlacesUpWhole_whenOtherPlacesFillBuildsCalledTypeAgainBesideFillReadingCallersLazyValue(caller: CallingMockCallerKind, pair: ReenteringWrapperPair) async throws {
		// The adopter’s shape, with `F` also building `B`, whose place `other` `LiveOther` fills, and `LiveOther`, which reads
		// no `log`, building `F` again: `F` is re-entered, and `Live` reads `Root`’s wrapper beside its place’s fields, so `api`
		// is passed up whole, and then `other`, whose fill calls `F`’s mock, which now passes `api` up.
		try await expectPassesPlacesUpWhole(
			mock: Self.otherFillReentersModules(caller: caller, pair: pair, layout: .otherLevel),
			caller: caller,
			wrapper: pair.wrapper,
			builders: [.api, .other],
			guards: PassedUpGuards(calledType: "C57A56ACC78091BE", root: "1F1794C07125A971"),
		)
	}

	@Test(arguments: CallingMockCallerKind.allCases, [ReenteringOtherPlaceLayout.placesLevel, .childOfOtherFill])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesBothPlacesUpWhole_whenOtherPlaceBuildingCalledTypeAgainMoves(caller: CallingMockCallerKind, layout: ReenteringOtherPlaceLayout) async throws {
		// As above, with `other` on `A`’s level beside `api`, or with `LiveOther`’s child building `F` again.
		let guards = switch layout {
		case .placesLevel:
			PassedUpGuards(calledType: "272F0F993A5E878A", root: "E7C05D3475C33E19")
		case .otherLevel, .childOfOtherFill:
			PassedUpGuards(calledType: "C57A56ACC78091BE", root: "1F1794C07125A971")
		}
		try await expectPassesPlacesUpWhole(
			mock: Self.otherFillReentersModules(caller: caller, pair: .lazilyInstantiatedInInstantiator, layout: layout),
			caller: caller,
			wrapper: .lazilyInstantiated,
			builders: [.api, .other],
			guards: guards,
		)
	}

	@Test(arguments: CallingMockCallerKind.allCases, ReenteringWrapperPair.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesBothPlacesUpWhole_whenPlaceOnCalledTypesRootReadsCallersLazyValueAndOtherPlacesFillBuildsCalledTypeAgain(caller: CallingMockCallerKind, pair: ReenteringWrapperPair) async throws {
		// `F` holds the place `api` on its own level, which `Live` fills, reading `Root`’s wrapper, and `B`, beneath `F`, holds
		// `other`, whose fill `LiveOther` reads no `log` and builds `F` again: `F` is re-entered, so `api` is passed up whole,
		// and then `other`. Filling both did not compile: the fill that builds `F` again took the wrapper optionally and
		// handed its instance to the re-entered call.
		try await expectPassesPlacesUpWhole(
			mock: Self.rootLevelReaderModules(caller: caller, pair: pair, variation: .plain),
			caller: caller,
			wrapper: pair.wrapper,
			builders: [.api, .other],
			guards: PassedUpGuards(calledType: "5DD5A60BEFB14B01", root: "DB0C331EDC45539A"),
		)
	}

	@Test(arguments: CallingMockCallerKind.allCases, [RootLevelReaderVariation.otherPlaceTwoLevelsDown, .erasedPlace, .receivedOnlyIfAvailable, .levelDeclaresValueAgainAboveOtherPlace])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesBothPlacesUpWhole_whenPlaceOnCalledTypesRootReadsCallersLazyValueInNeighbourShape(caller: CallingMockCallerKind, variation: RootLevelReaderVariation) async throws {
		// As above, with `B` a level further down, the place an `ErasedInstantiator<(), any Api>`, `Z` receiving `log` only if
		// available, or `B` instantiating a `log` of its own above `other`, whose fill then built `F` again with `B`’s wrapper,
		// where inline’s re-entered `Live` holds it.
		// An erased instantiator that forwards nothing takes the builder a plain place takes, `() -> any Api`.
		let builders = [PassedUpBuilder.api, .other]
		let guards: PassedUpGuards
		switch variation {
		case .otherPlaceTwoLevelsDown:
			guards = PassedUpGuards(calledType: "8616E1F4162A5020", root: "825F2EC2249B6A19")
		case .erasedPlace:
			guards = PassedUpGuards(calledType: "A63197EE513E1FDE", root: "E06FFE68D7695345")
		case .receivedOnlyIfAvailable:
			guards = PassedUpGuards(calledType: "BF0F8CB2899FAE4B", root: "18A4A48F2983414C")
		case .levelDeclaresValueAgainAboveOtherPlace:
			guards = PassedUpGuards(calledType: "1CCE88D3D7769787", root: "1BBF7E73652D4976")
		case .plain, .mockedTypeBetween:
			Issue.record("\(variation) has a test of its own")
			return
		}
		try await expectPassesPlacesUpWhole(
			mock: Self.rootLevelReaderModules(caller: caller, pair: .lazilyInstantiatedInInstantiator, variation: variation),
			caller: caller,
			wrapper: .lazilyInstantiated,
			builders: builders,
			guards: guards,
		)
	}

	@Test(arguments: CallingMockCallerKind.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesBothPlacesUpWholeInEveryMock_whenMockedTypeBetweenCallsCalledTypeThatIsReentered(caller: CallingMockCallerKind) async throws {
		// The first test above, with a mocked `Mid` between `Root` and `F`: the gate decides per called type and hole type for
		// the whole module, so `Mid`’s own mock passes both places up as `Root`’s does.
		// `Mid`’s mock is internal, so only a call in `App` reaches it.
		var calls = "    _ = Root.mock(apiBuilder: { StubApi() }, otherBuilder: { StubOther() })\n"
		if caller != .public {
			calls += "    _ = Mid.mock(apiBuilder: { StubApi() }, otherBuilder: { StubOther() })\n"
		}
		let handWrittenCall = "import Feat\n\nfinal class StubApi: Api {}\nfinal class StubOther: Other {}\n\nfunc callMock() {\n\(calls)}\n"
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(Self.rootLevelReaderModules(caller: caller, pair: .lazilyInstantiatedInInstantiator, variation: .mockedTypeBetween), callingMockCaller: caller.callingMockCaller, handWrittenCall: handWrittenCall),
			integration: .moduleInfo,
			compileVerification: .returningOutcomeOnly,
			filesToDelete: &filesToDelete,
		)
		if compileVerificationIsEnabled {
			let compilation = try #require(output.compilation)
			#expect(compilation.failure == nil, "\(compilation.failure.map { "\($0)" } ?? "")")
		}
		let generatedFile = try #require(output.modules["App"]?.generatedFiles["App.swift"])
		// A listed `Root`’s production tree comes first, and its mocks after it.
		let mocks = try #require(generatedFile.range(of: "#if DEBUG\n").map { String(generatedFile[$0.lowerBound...]) })
		let rootSignature = Self.mockSignature(of: "Root", in: mocks)
		let midSignature = Self.mockSignature(of: "Mid", in: mocks)
		#expect(rootSignature == "static func mock(\n        apiBuilder: @escaping () -> any Api,\n        otherBuilder: @escaping () -> any Other,\n        safeDIOverrides: SafeDIOverrides = .init()\n    ) -> Root {")
		#expect(midSignature == "static func mock(\n        apiBuilder: @escaping () -> any Api,\n        otherBuilder: @escaping () -> any Other,\n        safeDIOverrides: SafeDIOverrides = .init()\n    ) -> Mid {")
		guard caller == .internal else { return }
		#expect(generatedFile == generatedFileHeader + """
		#if canImport(Feat)
		import Feat
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Mid {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            log: (() -> Log)? = nil,
		            f: F.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                log: log,
		                f: f
		            )
		        }

		        var log: (() -> Log)? { __safeDI_storage.log }
		        var f: F.SafeDIOverrides { __safeDI_storage.f }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                log: (() -> Log)?,
		                f: F.SafeDIOverrides
		            ) {
		                self.log = log
		                self.f = f
		            }

		            let log: (() -> Log)?
		            let f: F.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiBuilder: @escaping () -> any Api,
		        otherBuilder: @escaping () -> any Other,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Mid {
		        let __safeDI_apiBuilder = apiBuilder
		        let __safeDI_otherBuilder = otherBuilder
		        let log = if let safeDIBuilder = safeDIOverrides.log { safeDIBuilder() } else { Log() }
		        \(Self.guardLine(calledType: "5DD5A60BEFB14B01"))
		        func __safeDI_f() -> F {
		            let apiBuilder: () -> any Api = __safeDI_apiBuilder
		            let otherBuilder: () -> any Other = __safeDI_otherBuilder
		            return F.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), otherBuilder: .init(__safeDI_noScope: otherBuilder), log: log, safeDIOverrides: safeDIOverrides.f)
		        }
		        let f: F = __safeDI_f()
		        return Mid(f: f)
		    }
		}
		#endif

		#if DEBUG
		extension Mid {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            f: F.SafeDIOverrides = .init(),
		            _ safeDIBuilder: ((F) -> Mid)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                f: f,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var f: F.SafeDIOverrides { __safeDI_storage.f }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: ((F) -> Mid)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                f: F.SafeDIOverrides,
		                safeDIBuilder: ((F) -> Mid)?
		            ) {
		                self.f = f
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let f: F.SafeDIOverrides
		            let safeDIBuilder: ((F) -> Mid)?
		        }
		    }
		}
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            log: (() -> Log)? = nil,
		            mid: Mid.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                log: log,
		                mid: mid
		            )
		        }

		        var log: (() -> Log)? { __safeDI_storage.log }
		        var mid: Mid.SafeDIMockConfiguration { __safeDI_storage.mid }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                log: (() -> Log)?,
		                mid: Mid.SafeDIMockConfiguration
		            ) {
		                self.log = log
		                self.mid = mid
		            }

		            let log: (() -> Log)?
		            let mid: Mid.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        apiBuilder: @escaping () -> any Api,
		        otherBuilder: @escaping () -> any Other,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let __safeDI_apiBuilder = apiBuilder
		        let __safeDI_otherBuilder = otherBuilder
		        func __safeDI_log() -> Log {
		            if let safeDIBuilder = safeDIOverrides.log { safeDIBuilder() } else { Log() }
		        }
		        let log = LazilyInstantiated<Log>(__safeDI_log)
		        func __safeDI_mid() -> Mid {
		            \(Self.guardLine(calledType: "5DD5A60BEFB14B01"))
		            func __safeDI_f() -> F {
		                let apiBuilder: () -> any Api = __safeDI_apiBuilder
		                let otherBuilder: () -> any Other = __safeDI_otherBuilder
		                return F.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), otherBuilder: .init(__safeDI_noScope: otherBuilder), log: log.instance, safeDIOverrides: safeDIOverrides.mid.f)
		            }
		            let f: F = __safeDI_f()
		            return if let safeDIBuilder = safeDIOverrides.mid.safeDIBuilder { safeDIBuilder(f) } else { Mid(f: f) }
		        }
		        let mid: Mid = __safeDI_mid()
		        return Root(log: log, mid: mid)
		    }
		}
		#endif
		""")
	}

	@Test(arguments: CallingMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesPlaceUpWhole_whenFillReadingCallersLazyValueCallsPublicMockThatBuildsCalledTypeAgain(caller: CallingMockCaller) async throws {
		// `Page`’s place `service` is filled by `DefaultService`, which reads `Screen`’s `LazilyInstantiated<Token>` and builds
		// `Book`, whose public mock builds `Page` again and so passes `Page`’s place up: `Page` is re-entered through `Book`’s
		// builders, and `service` is passed up whole. Filling it named a builder the mock does not take.
		let handWrittenCall = "import Core\n\nfinal class StubService: Service {}\n\nfunc callMock() {\n    _ = Screen.mock(serviceBuilder: { StubService() })\n}\n"
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(Self.crossCallLazyReentryModules(caller: caller), callingMockCaller: caller, handWrittenCall: handWrittenCall),
			integration: .moduleInfo,
			compileVerification: .returningOutcomeOnly,
			filesToDelete: &filesToDelete,
		)
		if compileVerificationIsEnabled {
			let compilation = try #require(output.compilation)
			#expect(compilation.failure == nil, "\(compilation.failure.map { "\($0)" } ?? "")")
		}
		let guardLine = "_ = Page.__safeDI_Page_mock_4A57B09DFB8A9D2C.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes."
		switch caller {
		case .internal:
			#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(Mid)
			import Mid
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            token: (() -> Token)? = nil,
			            page: ((@escaping () -> any Service) -> Page)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                token: token,
			                page: page
			            )
			        }

			        var token: (() -> Token)? { __safeDI_storage.token }
			        var page: ((@escaping () -> any Service) -> Page)? { __safeDI_storage.page }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                token: (() -> Token)?,
			                page: ((@escaping () -> any Service) -> Page)?
			            ) {
			                self.token = token
			                self.page = page
			            }

			            let token: (() -> Token)?
			            let page: ((@escaping () -> any Service) -> Page)?
			        }
			    }

			    static func mock(
			        serviceBuilder: @escaping () -> any Service,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let __safeDI_serviceBuilder = serviceBuilder
			        func __safeDI_token() -> Token {
			            if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
			        }
			        let token = LazilyInstantiated<Token>(__safeDI_token)
			        \(guardLine)
			        func __safeDI_page() -> Page {
			            let serviceBuilder: () -> any Service = __safeDI_serviceBuilder
			            return if let safeDIBuilder = safeDIOverrides.page { safeDIBuilder(serviceBuilder) } else { Page.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder)) }
			        }
			        let page: Page = __safeDI_page()
			        return Screen(token: token, page: page)
			    }
			}
			#endif
			""")
		case .public:
			#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(Mid)
			import Mid
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDIMockScope_Service {
			        nonisolated public struct page_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let page: (page_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>

			            public init(page: @escaping (page_Values) -> Page.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>) {
			                self.page = page
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(page: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            token: (() -> Token)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                token: token
			            )
			        }

			        public var token: (() -> Token)? { __safeDI_storage.token }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                token: (() -> Token)?
			            ) {
			                self.token = token
			            }

			            let token: (() -> Token)?
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
			        func __safeDI_token() -> Token {
			            if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
			        }
			        let token = LazilyInstantiated<Token>(__safeDI_token)
			        \(guardLine)
			        let page = Page.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.page(SafeDIMockScope_Service.page_Values()))
			        return Screen(token: token, page: page)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_7E006A95F19F521D {}
			}
			#endif
			""")
		}
	}

	@Test(arguments: CallingMockCallerKind.allCases, ReenteredThroughAnotherCallsFillLayout.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesPlacesUpWhole_whenCallReadingCallersLazyValueIsReenteredThroughAnotherCallsFill(caller: CallingMockCallerKind, layout: ReenteredThroughAnotherCallsFillLayout) async throws {
		// `F`’s place `api`, whose fill `Live` reads `Root`’s `LazilyInstantiated<Log>`, is inside a fill of `G`’s place, and
		// `G` is built again inside `F`’s fills, through a third called type `H` where `layout` says so: `F` is re-entered
		// through the fills of the calls its fills make, so `api` is passed up whole, and so is `G`’s place, whose fill builds
		// `F`, which now passes a builder up (`DependencyTreeGenerator.holeTypesTheFillGatesPassUp(of:in:lazilyHeldValues:)`). `Root`’s mock
		// takes `G`’s builder, whatever is between `G` and the call that re-enters `F`.
		try await expectPassesPlacesUpWhole(
			mock: Self.reenteredThroughAnotherCallsFillModules(caller: caller, layout: layout),
			caller: caller,
			wrapper: .lazilyInstantiated,
			builders: [.gApi],
			guards: PassedUpGuards(calledType: "2C26D9DE7BF3486B", root: "71059A40DE3B930C"),
			call: .g,
		)
	}

	@Test(arguments: CallingMockCallerKind.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesPlaceOnCalledTypesRootUpWhole_whenFillReadingCallersLazyValueBuildsAnotherCalledTypeThatBuildsItAgain(caller: CallingMockCallerKind) async throws {
		// The cell below, with `LiveG` building `F` again: `F` is re-entered through `G`’s fill, so `api`, on `F`’s root
		// level, is passed up whole (`DependencyTreeGenerator.holeTypesTheFillGatesPassUp(of:in:lazilyHeldValues:)`), where filling it named a
		// builder of `G`’s the mock does not take.
		try await expectPassesPlacesUpWhole(
			mock: Self.secondCallFromCalledTypesRootModules(caller: caller, secondCallBuildsFirstAgain: true),
			caller: caller,
			wrapper: .lazilyInstantiated,
			builders: [.api],
			guards: PassedUpGuards(calledType: "7D841B2EEDD2A0BB", root: "0C12B745593904E0"),
		)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "Compiles Swift only when compile verification is enabled"), arguments: CallingMockCallerKind.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceOnCalledTypesRootAsInline_whenFillReadingCallersLazyValueBuildsAnotherCalledType(caller: CallingMockCallerKind) async throws {
		// `Root` builds `F`, whose place `api` is on its root level: `Live` fills it, reads `Root`’s `LazilyInstantiated<Log>`
		// and builds `G`, a second called type, whose fill builds nothing called, so no call is re-entered. `F`’s mock binds
		// `log` by value, so the fill reads `Root`’s wrapper and hands its instance to `G`’s mock, as inline.
		try await expectValuesEqualInline(
			mock: Self.secondCallFromCalledTypesRootModules(caller: caller, secondCallBuildsFirstAgain: false),
			inline: Self.secondCallFromCalledTypesRootInlineModules(secondCallBuildsFirstAgain: false),
			caller: caller.callingMockCaller,
			handWrittenCall: "import Feat\n\nfunc callMock() {\n    _ = Root.mock()\n}\n",
			probes: Self.secondCallFromCalledTypesRootProbes,
		)
	}

	// MARK: Tests – a place passed up whole where two places’ fills read different lazy values

	@Test(arguments: CallingMockCallerKind.allCases, PlacesDisagreeVariation.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesPlaceUpWhole_whenPlacesOfOneHoleTypeReadDifferentLazyValuesBesideTheirFields(caller: CallingMockCallerKind, variation: PlacesDisagreeVariation) async throws {
		// `F` holds `api` twice: on `A`’s level, where `Live` reads `Root`’s wrapper beside that place’s fields, and beneath a
		// level that instantiates a `log` of its own, `Live` reading that level’s field. One fill serves both places, so the
		// hole type is passed up whole, where filling it named a builder the mock does not take, as main’s calling mock passes
		// it up. No call re-enters `F`. Where `F`’s by-value copy of `log` reaches the first place, no level that holds only
		// the copy can hand `Live` the wrapper. Where `F` holds no copy (`levelBesidePlaceWithoutCopy`), or the second place is
		// an `ErasedInstantiator` (`levelBesideErasedPlace`), filling both places built what inline builds, so passing them up
		// is the gate’s stated cost (`DependencyTreeGenerator.holeTypesTheFillGatesPassUp(of:in:lazilyHeldValues:)`).
		var builders = [PassedUpBuilder.api]
		var guards = PassedUpGuards(calledType: "F1E8D579CB81D9A6", root: "60281D4498053F73")
		var calledMockTakesLog = true
		switch variation {
		case .levelBesidePlace:
			break
		case .levelBesidePlaceWithoutCopy:
			guards = PassedUpGuards(calledType: "B3A1B35B307DAED5", root: "FC5216D443EEF05F")
			calledMockTakesLog = false
		case .levelBesideErasedPlace:
			guards = PassedUpGuards(calledType: "44EB5F20039A77EF", root: "F7B7A5B98F14BF14")
		case .levelInSendableFunctionBesidePlace:
			builders = [.api, .sendableApi]
			guards = PassedUpGuards(calledType: "52604B0DC106621C", root: "1BDB61EC60CB728C")
		case .levelInSendableFunctionBesidePlaceReceivedOnlyIfAvailable:
			builders = [.api, .sendableApi]
			guards = PassedUpGuards(calledType: "DB1816B406033BDF", root: "14D0C478E166B42F")
		}
		try await expectPassesPlacesUpWhole(
			mock: Self.placesDisagreeModules(caller: caller, variation: variation),
			caller: caller,
			wrapper: variation.wrapper,
			builders: builders,
			guards: guards,
			calledMockTakesLog: calledMockTakesLog,
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
			valueProbes: [DifferentialValueProbe(name: "Feature", expression: "Mid.Feature.mock(gadgetBuilder: { Mid.StubGadget() })", knownRightExpression: "Mid.Feature(gadgetBuilder: { Mid.StubGadget() })")],
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

	@Test(arguments: [MockConditionCaller.internal, .public, .listed], MockConditionInactiveBuild.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesMockWithoutTwinsError_whenBuildLeavesMockConditionInactive(caller: MockConditionCaller, build: MockConditionInactiveBuild) async throws {
		// The fill of the error above, in a build that does not tell the tool `DEBUG`, the mock condition: the tool checks
		// the fill only where the generated mocks compile, so it reports nothing and passes the place up. A release build
		// compiles no generated mock; a debug build whose integration does not report `DEBUG` compiles the mock, which
		// compiles.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.fillInstantiatingGizmoModules(
				caller: caller.attribute,
				callee: CalledTypeDeclaration.seamAndPublicMock.attribute,
				defaultServiceProperties: ["names: [String]"],
				listsScreen: caller == .listed,
				appIsReleaseConfiguration: build == .release,
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)

		#expect(output.modules["App"]?.generatedFiles == caller.expectedFilesWhereMockConditionIsInactive)
	}

	@Test(arguments: [MockConditionCaller.internal, .public, .listed], MockConditionInactiveBuild.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderOfWhatFillInstantiates_whenBuildLeavesMockConditionInactive(caller: MockConditionCaller, build: MockConditionInactiveBuild) async throws {
		// The neighbour of the cell above whose fill instantiates `any Gizmo`, which no declaration fulfills either but which
		// a hole can be: the mock takes a builder for it and fills the place, as in a build that compiles the mocks.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.fillInstantiatingGizmoModules(
				caller: caller.attribute,
				callee: CalledTypeDeclaration.seamAndPublicMock.attribute,
				defaultServiceProperties: ["gizmo: any Gizmo"],
				listsScreen: caller == .listed,
				appIsReleaseConfiguration: build == .release,
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)

		switch caller {
		case .internal, .listed:
			#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
			        gizmoBuilder: @escaping () -> any Gizmo,
			        serviceBuilder: (() -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_fillBody_A303510A72F6F6C4() -> any Service {
			            func __safeDI_service() -> DefaultService {
			                let gizmo: any Gizmo = gizmoBuilder()
			                return DefaultService(gizmo: gizmo)
			            }
			            let service: any Service = __safeDI_service()
			            return service
			        }
			        func __safeDI_panel() -> Panel {
			            func __safeDI_serviceBuilder_Panel_service(_ scope: Panel.SafeDIMockScope_Service.service_Values) -> any Service {
			                return __safeDI_fillBody_A303510A72F6F6C4()
			            }
			            func __safeDI_serviceBuilder_Panel_Row_Scope_service(_ scope: Panel.SafeDIMockScope_Service.Row_Scope.service_Values) -> any Service {
			                return __safeDI_fillBody_A303510A72F6F6C4()
			            }
			            func __safeDI_serviceBuilder_Panel() -> Panel.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(row: { _ in __safeDI_serviceBuilder_Panel_Row_Scope() }, service: { scope in __safeDI_serviceBuilder_Panel_service(scope) })
			            }
			            func __safeDI_serviceBuilder_Panel_Row_Scope() -> Panel.SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Panel_Row_Scope_service(scope) })
			            }
			            _ = Panel.__safeDI_Panel_mock_9A2B32943A6C59F5.self // If this line does not compile, compile the code SafeDI generates for module Up into Up: under Bazel, add Up’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Panel.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Panel(), safeDIOverrides: safeDIOverrides.panel)
			        }
			        let panel: Panel = __safeDI_panel()
			        return Screen(panel: panel)
			    }
			}
			#endif
			"""])
		case .public:
			#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif
			#if canImport(Up)
			import Up
			#endif

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDIMockScope_Gizmo {
			        nonisolated public struct panel_serviceBuilder_Values {}

			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct gizmo_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let gizmo: (gizmo_Values) -> __safeDI_Built

			                public init(gizmo: @escaping (gizmo_Values) -> __safeDI_Built) {
			                    self.gizmo = gizmo
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(gizmo: { _ in __safeDI_builder() })
			                }
			            }
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let panel_serviceBuilder: (panel_serviceBuilder_Values) -> Panel.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gizmo.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(panel_serviceBuilder: @escaping (panel_serviceBuilder_Values) -> Panel.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gizmo.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.panel_serviceBuilder = panel_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(panel_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
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
			        gizmoBuilder: @escaping () -> any Gizmo,
			        serviceBuilder: (() -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(gizmoBuilder: .init(__safeDI_noScope: gizmoBuilder), serviceBuilder: serviceBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        gizmoBuilder __safeDI_gizmoBuilder: Screen.SafeDIMockScope_Gizmo.__safeDI_Builder<any Gizmo>,
			        serviceBuilder __safeDI_serviceBuilder: (() -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let __safeDI_gizmoBuilder_panel_serviceBuilder = __safeDI_gizmoBuilder.panel_serviceBuilder(SafeDIMockScope_Gizmo.panel_serviceBuilder_Values())
			        func __safeDI_panel() -> Panel {
			            func __safeDI_serviceBuilder_Panel_service(_ scope: Panel.SafeDIMockScope_Service.service_Values, __safeDI_panel_serviceBuilder: SafeDIMockScope_Gizmo.DefaultService_Scope.__safeDI_Builder<any Gizmo>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gizmo: any Gizmo = __safeDI_panel_serviceBuilder.gizmo(SafeDIMockScope_Gizmo.DefaultService_Scope.gizmo_Values())
			                    return DefaultService(gizmo: gizmo)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Panel_Row_Scope_service(_ scope: Panel.SafeDIMockScope_Service.Row_Scope.service_Values, __safeDI_panel_serviceBuilder: SafeDIMockScope_Gizmo.DefaultService_Scope.__safeDI_Builder<any Gizmo>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let gizmo: any Gizmo = __safeDI_panel_serviceBuilder.gizmo(SafeDIMockScope_Gizmo.DefaultService_Scope.gizmo_Values())
			                    return DefaultService(gizmo: gizmo)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Panel(up: Panel.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gizmo.DefaultService_Scope.__safeDI_Builder<any Gizmo>>) -> Panel.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(row: { values in __safeDI_serviceBuilder_Panel_Row_Scope(up: up.row(values)) }, service: { scope in __safeDI_serviceBuilder_Panel_service(scope, __safeDI_panel_serviceBuilder: up.service(scope)) })
			            }
			            func __safeDI_serviceBuilder_Panel_Row_Scope(up: Panel.SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<SafeDIMockScope_Gizmo.DefaultService_Scope.__safeDI_Builder<any Gizmo>>) -> Panel.SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Panel_Row_Scope_service(scope, __safeDI_panel_serviceBuilder: up.service(scope)) })
			            }
			            _ = Panel.__safeDI_Panel_mock_9A2B32943A6C59F5.self // If this line does not compile, compile the code SafeDI generates for module Up into Up: under Bazel, add Up’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Panel.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Panel(up: __safeDI_gizmoBuilder_panel_serviceBuilder), safeDIOverrides: safeDIOverrides.panel)
			        }
			        let panel: Panel = __safeDI_panel()
			        return Screen(panel: panel)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_212BFE574AEA9F41 {}
			}
			#endif
			"""])
		}
	}

	@Test(arguments: [MockConditionCaller.internal, .public, .listed], MockConditionInactiveBuild.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceWithFillReceivingTypeOnlyIfAvailable_whenBuildLeavesMockConditionInactive(caller: MockConditionCaller, build: MockConditionInactiveBuild) async throws {
		// The neighbour of the cell above whose fill receives `[String]` only if available, which nothing provides: production
		// fills the place with `nil` for it, so the mock does too.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.fillInstantiatingGizmoModules(
				caller: caller.attribute,
				callee: CalledTypeDeclaration.seamAndPublicMock.attribute,
				defaultServiceProperties: [],
				defaultServiceDeclarations: ["@Received(onlyIfAvailable: true) public let names: [String]?"],
				listsScreen: caller == .listed,
				appIsReleaseConfiguration: build == .release,
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)

		switch caller {
		case .internal, .listed:
			#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
			            panel: Panel.SafeDIOverrides = .init(),
			            names: [String]? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                panel: panel
			            )
			            self.names = names
			        }

			        var panel: Panel.SafeDIOverrides { __safeDI_storage.panel }
			        let names: [String]?

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
			        serviceBuilder: (() -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let names: [String]? = safeDIOverrides.names
			        func __safeDI_panel() -> Panel {
			            func __safeDI_serviceBuilder_Panel() -> Panel.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(
			                    row: { _ in __safeDI_serviceBuilder_Panel_Row_Scope() },
			                    service: { _ in
			                        let service: any Service = DefaultService(names: names)
			                        return service
			                    }
			                )
			            }
			            func __safeDI_serviceBuilder_Panel_Row_Scope() -> Panel.SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<any Service> {
			                .init(service: { _ in
			                    let service: any Service = DefaultService(names: names)
			                    return service
			                })
			            }
			            _ = Panel.__safeDI_Panel_mock_9A2B32943A6C59F5.self // If this line does not compile, compile the code SafeDI generates for module Up into Up: under Bazel, add Up’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Panel.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Panel(), safeDIOverrides: safeDIOverrides.panel)
			        }
			        let panel: Panel = __safeDI_panel()
			        return Screen(panel: panel)
			    }
			}
			#endif
			"""])
		case .public:
			#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif
			#if canImport(Up)
			import Up
			#endif

			#if DEBUG
			extension Screen {
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
			        serviceBuilder: (() -> any Service)? = nil,
			        names: [String]? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(serviceBuilder: serviceBuilder, names: names, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        serviceBuilder __safeDI_serviceBuilder: (() -> any Service)? = nil,
			        names: [String]? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_panel() -> Panel {
			            func __safeDI_serviceBuilder_Panel() -> Panel.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(
			                    row: { _ in __safeDI_serviceBuilder_Panel_Row_Scope() },
			                    service: { _ in
			                        let service: any Service = DefaultService(names: names)
			                        return service
			                    }
			                )
			            }
			            func __safeDI_serviceBuilder_Panel_Row_Scope() -> Panel.SafeDIMockScope_Service.Row_Scope.__safeDI_Builder<any Service> {
			                .init(service: { _ in
			                    let service: any Service = DefaultService(names: names)
			                    return service
			                })
			            }
			            _ = Panel.__safeDI_Panel_mock_9A2B32943A6C59F5.self // If this line does not compile, compile the code SafeDI generates for module Up into Up: under Bazel, add Up’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Panel.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Panel(), safeDIOverrides: safeDIOverrides.panel)
			        }
			        let panel: Panel = __safeDI_panel()
			        return Screen(panel: panel)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_6D2DA1ED6C1746F7 {}
			}
			#endif
			"""])
		}
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
				knownRightExpression: "{ () -> (App.Screen, Int) in var count = 0; let screen = App.Screen(gizmoBuilder: { count += 1; return App.StubGizmo() }); return (screen, count) }()",
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
				knownRightExpression: "App.Screen(gizmoSendableBuilder: { App.StubGizmo() })",
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
				knownRightExpression: "App.Screen(defaultGizmo_GizmoBuilder: { App.DefaultGizmo(id: $0) })",
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
			valueProbes: [DifferentialValueProbe(name: "Screen", expression: "App.Screen.mock(gizmoBuilder: { App.StubGizmo() })", knownRightExpression: "App.Screen(gizmoBuilder: { App.StubGizmo() })")],
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
			valueProbes: [DifferentialValueProbe(name: "Screen", expression: "App.Screen.mock(gizmoBuilder: { App.StubGizmo() })", knownRightExpression: "App.Screen(gizmoBuilder: { App.StubGizmo() })")],
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
				knownRightExpression: "App.Screen(gizmoBuilder: { App.StubGizmo() }, widgetBuilder: { App.StubWidget() })",
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
			valueProbes: [DifferentialValueProbe(name: "Screen", expression: "App.Screen.mock(gizmoBuilder: { App.StubGizmo() })", knownRightExpression: "App.Screen(gizmoBuilder: { App.StubGizmo() })")],
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
			valueProbes: [DifferentialValueProbe(name: "Screen", expression: "App.Screen.mock(gizmoBuilder: { App.StubGizmo() }, gizmo: App.StubGizmo())", knownRightExpression: "App.Screen(gizmoBuilder: { App.StubGizmo() })")],
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
			"static func mock(\n        gadgetBuilder: (() -> any Gadget)? = nil,\n        serviceBuilder: (() -> any Service)? = nil,\n        safeDIOverrides: SafeDIOverrides = .init()\n    ) -> HubScreen {"
		case .public:
			"static func mock(\n        gadgetBuilder: (() -> any Gadget)? = nil,\n        serviceBuilder: (() -> any Service)? = nil,\n        token: Token? = nil,\n        safeDIOverrides: SafeDIOverrides = .init()\n    ) -> HubScreen {"
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
		let modules = Self.modules(mock, callingMockCaller: caller, handWrittenCall: handWrittenCall)
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

	/// `mock`’s modules with `handWrittenCall`, a call of the calling mock’s `mock()`: in the caller’s module, the last of
	/// `mock`, for an internal caller, and in a module that depends on every module of `mock` for a `.public` one.
	private static func modules(_ mock: [ModuleFixture], callingMockCaller caller: CallingMockCaller, handWrittenCall: String) -> [ModuleFixture] {
		let callerModule = mock[mock.count - 1]
		return switch caller {
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
	}

	/// Expects `Root`’s calling mock of `mock`, whose module is `App` and whose tree holds `log` in `wrapper` and calls `F`’s
	/// public mock, to pass `builders` up whole, as `passedUpRootMockSection` spells its mock, and to compile with a call of
	/// its `mock()` that passes a stub for each builder. The whole generated file is compared, but for a listed caller,
	/// whose file holds its production tree first, of which only the mock is compared. `calledMockTakesLog` says whether
	/// `F`’s mock takes `log`. Where `call` says so, `Root` calls `G`’s public mock, which it builds as `g`, rather than `F`’s.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectPassesPlacesUpWhole(
		mock: [ModuleFixture],
		caller: CallingMockCallerKind,
		wrapper: CallerLazyWrapper,
		builders: [PassedUpBuilder],
		guards: PassedUpGuards,
		calledMockTakesLog: Bool = true,
		call: PassedUpCall = .f,
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		var stubs = ""
		if builders.contains(where: { $0.builtType == "any Api" }) {
			stubs += "final class StubApi: Api {}\n"
		}
		if builders.contains(where: { $0.builtType == "any Api2" }) {
			stubs += "final class StubApi2: Api2 {}\n"
		}
		if builders.contains(where: { $0.builtType == "any GApi" }) {
			stubs += "final class StubGApi: GApi {}\n"
		}
		if builders.contains(where: { $0.builtType == "any Other" }) {
			stubs += "final class StubOther: Other {}\n"
		}
		let arguments = builders.map { "\($0.label): \($0.stubArgument)" }.joined(separator: ", ")
		let handWrittenCall = "import Feat\n\n\(stubs)\nfunc callMock() {\n    _ = Root.mock(\(arguments))\n}\n"
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(mock, callingMockCaller: caller.callingMockCaller, handWrittenCall: handWrittenCall),
			integration: .moduleInfo,
			compileVerification: .returningOutcomeOnly,
			filesToDelete: &filesToDelete,
		)
		if compileVerificationIsEnabled {
			let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
			#expect(compilation.failure == nil, "\(compilation.failure.map { "\($0)" } ?? "")", sourceLocation: sourceLocation)
		}
		let generatedFile = try #require(output.modules["App"]?.generatedFiles["App.swift"], sourceLocation: sourceLocation)
		let mockSection = Self.passedUpRootMockSection(caller: caller.callingMockCaller, wrapper: wrapper, builders: builders, guards: guards, calledMockTakesLog: calledMockTakesLog, call: call)
		switch caller {
		case .internal, .public:
			let expectedFile = generatedFileHeader + "#if canImport(Feat)\nimport Feat\n#endif\n#if canImport(SafeDI)\nimport SafeDI\n#endif\n\n" + mockSection
			#expect(generatedFile == expectedFile, sourceLocation: sourceLocation)
		case .listed:
			let generatedMockSection = generatedFile.range(of: "#if DEBUG\n").map { String(generatedFile[$0.lowerBound...]) }
			#expect(generatedMockSection == mockSection, sourceLocation: sourceLocation)
		}
	}

	/// A builder a calling mock passes up whole: its label, the type `mock()` takes it as, the type it builds, the enum a
	/// `.public` mock’s builder struct is declared in and the type of the closure its `__safeDI_noScope` initializer takes,
	/// whether it is the `@Sendable` family’s, and the stub a hand-written call passes for it.
	struct PassedUpBuilder {
		let label: String
		let readableType: String
		let builtType: String
		let enumName: String
		let noScopeClosureType: String
		let isSendable: Bool
		let stubArgument: String

		static let api = PassedUpBuilder(label: "apiBuilder", readableType: "() -> any Api", builtType: "any Api", enumName: "SafeDIMockScope_Api", noScopeClosureType: "() -> __safeDI_Built", isSendable: false, stubArgument: "{ StubApi() }")
		static let sendableApi = PassedUpBuilder(label: "apiSendableBuilder", readableType: "@Sendable () -> any Api", builtType: "any Api", enumName: "SafeDISendableMockScope_Api", noScopeClosureType: "@Sendable () -> __safeDI_Built", isSendable: true, stubArgument: "{ StubApi() }")
		static let liveApi = PassedUpBuilder(label: "live_ApiBuilder", readableType: "ErasedInstantiator<Int, any Api>.Builder", builtType: "any Api", enumName: "SafeDIMockScope_Live_Api", noScopeClosureType: "ErasedInstantiator<Int, __safeDI_Built>.Builder", isSendable: false, stubArgument: "{ _ in StubApi() }")
		static let api2 = PassedUpBuilder(label: "api2Builder", readableType: "() -> any Api2", builtType: "any Api2", enumName: "SafeDIMockScope_Api2", noScopeClosureType: "() -> __safeDI_Built", isSendable: false, stubArgument: "{ StubApi2() }")
		static let other = PassedUpBuilder(label: "otherBuilder", readableType: "() -> any Other", builtType: "any Other", enumName: "SafeDIMockScope_Other", noScopeClosureType: "() -> __safeDI_Built", isSendable: false, stubArgument: "{ StubOther() }")
		static let gApi = PassedUpBuilder(label: "gApiBuilder", readableType: "() -> any GApi", builtType: "any GApi", enumName: "SafeDIMockScope_GApi", noScopeClosureType: "() -> __safeDI_Built", isSendable: false, stubArgument: "{ StubGApi() }")

		/// The member of the builder struct the call of `call`’s mock reads.
		func member(of call: PassedUpCall) -> String {
			isSendable ? "\(call.label)_Sendable" : call.label
		}
	}

	/// The called type whose public mock `Root` calls, and the label `Root` builds it under.
	struct PassedUpCall {
		let label: String
		let type: String

		static let f = PassedUpCall(label: "f", type: "F")
		static let g = PassedUpCall(label: "g", type: "G")
	}

	/// The hashes of the guard enums of `F`’s mock, which `Root`’s mock names, and of `Root`’s, which a `.public` mock
	/// declares.
	struct PassedUpGuards {
		let calledType: String
		let root: String?
	}

	/// The line before a call of `call`’s mock that names its guard enum.
	private static func guardLine(calledType: String, call: PassedUpCall = .f) -> String {
		"_ = \(call.type).__safeDI_\(call.type)_mock_\(calledType).self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes."
	}

	/// The mock SafeDI generates for `Root`, which instantiates `log` in `wrapper` and `f: F`, where it passes `builders` up
	/// whole: `mock()` takes each, and hands `F`’s mock each, with `log`’s instance, as main’s calling mock did for a place it
	/// passes up. A `.public` mock declares each builder’s struct, which its caller fills or passes up. Where
	/// `calledMockTakesLog` is `false`, `F`’s mock takes no `log`. Where `call` says so, `Root` builds `g: G` and calls `G`’s
	/// mock instead.
	private static func passedUpRootMockSection(caller: CallingMockCaller, wrapper: CallerLazyWrapper, builders: [PassedUpBuilder], guards: PassedUpGuards, calledMockTakesLog: Bool = true, call: PassedUpCall = .f) -> String {
		let access = caller == .public ? "public " : ""
		let logArgument = calledMockTakesLog ? "log: log.instance, " : ""
		let sendable = wrapper == .sendableLazilyInstantiated ? "@Sendable " : ""
		var logBinding = "        func __safeDI_log() -> Log {\n            if let safeDIBuilder = safeDIOverrides.log { safeDIBuilder() } else { Log() }\n        }\n"
		if wrapper == .sendableLazilyInstantiated {
			logBinding = "        let __safeDI_log__safeDIBuilder = safeDIOverrides.log\n        @Sendable nonisolated func __safeDI_log() -> Log {\n            if let safeDIBuilder = __safeDI_log__safeDIBuilder { safeDIBuilder() } else { Log() }\n        }\n"
		}
		logBinding += "        let log = \(wrapper.name)<Log>(__safeDI_log)\n"
		let label = call.label
		let type = call.type
		var section = "#if DEBUG\nextension Root {\n"
		if caller == .public {
			for builder in builders {
				let valuesType = "\(builder.member(of: call))_Values"
				let closureAttributes = builder.isSendable ? "@Sendable " : ""
				let builderConformance = builder.isSendable ? ": Sendable" : ""
				section += "    nonisolated public enum \(builder.enumName) {\n"
				section += "        nonisolated public struct \(valuesType): Sendable {}\n\n"
				section += "        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.\n"
				section += "        nonisolated public struct __safeDI_Builder<__safeDI_Built>\(builderConformance) {\n"
				section += "            public let \(builder.member(of: call)): \(closureAttributes)(\(valuesType)) -> \(type).\(builder.enumName).__safeDI_Builder<__safeDI_Built>\n\n"
				section += "            public init(\(builder.member(of: call)): @escaping \(closureAttributes)(\(valuesType)) -> \(type).\(builder.enumName).__safeDI_Builder<__safeDI_Built>) {\n"
				section += "                self.\(builder.member(of: call)) = \(builder.member(of: call))\n"
				section += "            }\n\n"
				section += "            public init(__safeDI_noScope __safeDI_builder: @escaping \(builder.noScopeClosureType)) {\n"
				section += "                self.init(\(builder.member(of: call)): { _ in .init(__safeDI_noScope: __safeDI_builder) })\n"
				section += "            }\n"
				section += "        }\n"
				section += "    }\n\n"
			}
		}
		section += "    /// Overrides for the mock dependency tree.\n"
		section += "    \(caller == .public ? "nonisolated public " : "")struct SafeDIOverrides {\n"
		section += "        \(access)init(\n"
		section += "            log: (\(sendable)() -> Log)? = nil,\n"
		section += "            \(label): \(type).SafeDIOverrides = .init()\n"
		section += "        ) {\n"
		section += "            __safeDI_storage = __safeDI_Storage(\n"
		section += "                log: log,\n"
		section += "                \(label): \(label)\n"
		section += "            )\n"
		section += "        }\n\n"
		section += "        \(access)var log: (\(sendable)() -> Log)? { __safeDI_storage.log }\n"
		section += "        \(access)var \(label): \(type).SafeDIOverrides { __safeDI_storage.\(label) }\n\n"
		section += "        private let __safeDI_storage: __safeDI_Storage\n\n"
		section += "        private final class __safeDI_Storage {\n"
		section += "            init(\n"
		section += "                log: (\(sendable)() -> Log)?,\n"
		section += "                \(label): \(type).SafeDIOverrides\n"
		section += "            ) {\n"
		section += "                self.log = log\n"
		section += "                self.\(label) = \(label)\n"
		section += "            }\n\n"
		section += "            let log: (\(sendable)() -> Log)?\n"
		section += "            let \(label): \(type).SafeDIOverrides\n"
		section += "        }\n"
		section += "    }\n\n"
		section += "    \(access)static func mock(\n"
		for builder in builders {
			section += "        \(builder.label): @escaping \(builder.readableType),\n"
		}
		section += "        safeDIOverrides: SafeDIOverrides = .init()\n"
		section += "    ) -> Root {\n"
		switch caller {
		case .internal:
			for builder in builders {
				section += "        let __safeDI_\(builder.label) = \(builder.label)\n"
			}
			section += logBinding
			section += "        \(guardLine(calledType: guards.calledType, call: call))\n"
			section += "        func __safeDI_\(label)() -> \(type) {\n"
			for builder in builders {
				section += "            let \(builder.label): \(builder.readableType) = __safeDI_\(builder.label)\n"
			}
			let arguments = builders.map { "\($0.label): .init(__safeDI_noScope: \($0.label))" }.joined(separator: ", ")
			section += "            return \(type).__safeDI_mock(\(arguments), \(logArgument)safeDIOverrides: safeDIOverrides.\(label))\n"
			section += "        }\n"
			section += "        let \(label): \(type) = __safeDI_\(label)()\n"
			section += "        return Root(log: log, \(label): \(label))\n"
			section += "    }\n"
			section += "}\n"
		case .public:
			let forwarded = builders.map { "\($0.label): .init(__safeDI_noScope: \($0.label))" }.joined(separator: ", ")
			section += "        Root.__safeDI_mock(\(forwarded), safeDIOverrides: safeDIOverrides)\n"
			section += "    }\n\n"
			section += "    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.\n"
			section += "    public static func __safeDI_mock(\n"
			for builder in builders {
				section += "        \(builder.label) __safeDI_\(builder.label): Root.\(builder.enumName).__safeDI_Builder<\(builder.builtType)>,\n"
			}
			section += "        safeDIOverrides: SafeDIOverrides = .init()\n"
			section += "    ) -> Root {\n"
			section += logBinding
			section += "        \(guardLine(calledType: guards.calledType, call: call))\n"
			let arguments = builders.map { builder in
				"\(builder.label): __safeDI_\(builder.label).\(builder.member(of: call))(\(builder.enumName).\(builder.member(of: call))_Values())"
			}.joined(separator: ", ")
			section += "        let \(label) = \(type).__safeDI_mock(\(arguments), \(logArgument)safeDIOverrides: safeDIOverrides.\(label))\n"
			section += "        return Root(log: log, \(label): \(label))\n"
			section += "    }\n"
			section += "}\n\n"
			section += "extension Root {\n"
			section += "    public enum __safeDI_Root_mock_\(guards.root ?? "") {}\n"
			section += "}\n"
		}
		section += "#endif"
		return section
	}

	// MARK: Fixtures

	/// The adopter’s shape: `F`, a seam and public mock in module `Feat`, builds `A`, whose initializer `App` cannot call, so
	/// its place is a level below `F`’s root, and `Z`, which receives `log`, so `F`’s mock binds `log` by value. `Live` fills
	/// the place and receives `log` in `wrapper`’s form, which `Root` instantiates. Where `listsCaller`, module `App` lists
	/// `Root` in `additionalMocksToGenerate`.
	private static func lazyValueBelowCalledRootModules(caller: String, callee: String, wrapper: CallerLazyWrapper, place: CalledMockPlace, listsCaller: Bool = false, receivesOnlyIfAvailable: Bool = false, layout: LazyValueLayout = .belowRoot) -> [ModuleFixture] {
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
				"FeatTypes.swift": lazyValueBelowCalledRootFeatureTypes(callee: callee, place: place, receivesOnlyIfAvailable: receivesOnlyIfAvailable, layout: layout),
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: appFiles, dependencies: ["Feat"]),
		]
	}

	/// `lazyValueBelowCalledRootModules`’ types in one module, `Root` a root: what inline builds.
	private static func lazyValueBelowCalledRootInlineModules(wrapper: CallerLazyWrapper, place: CalledMockPlace, receivesOnlyIfAvailable: Bool = false, layout: LazyValueLayout = .belowRoot) -> [ModuleFixture] {
		[
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"AppTypes.swift": lazyValueBelowCalledRootFeatureTypes(callee: "@Instantiable", place: place, receivesOnlyIfAvailable: receivesOnlyIfAvailable, layout: layout) + """


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

	/// `lazyValueBelowCalledRootModules`’ shape with a fill that builds the called type again: `Live` also instantiates
	/// `fBuilder: Instantiator<F>`, so the call of `F`’s mock inside the fill re-enters the call’s root level function.
	/// `Root` holds `log` as `rootLog`, and `Live` receives it as `fillLog`; `layout` says where the place is. Where
	/// `redeclaredAboveCall`, `Live` instantiates `m: M` instead, which instantiates a `log` of its own as `fillLog`, and
	/// `fBuilder`.
	private static func reenteringCallModules(caller: String, rootLog: String, fillLog: String, place: CalledMockPlace, listsCaller: Bool = false, redeclaredAboveCall: Bool = false, layout: LazyValueLayout = .belowRoot) -> [ModuleFixture] {
		var appFiles = [
			"AppTypes.swift": """
			import Feat
			import SafeDI

			\(reenteringFill(fillLog: fillLog, place: place, redeclaredAboveCall: redeclaredAboveCall))

			\(caller)
			public final class Root: Instantiable {
			    public init(log: \(rootLog), f: F) {
			        self.log = log
			        self.f = f
			    }

			    @Instantiated public let log: \(rootLog)
			    @Instantiated public let f: F
			}
			""",
		]
		if listsCaller {
			appFiles["SafeDIConfiguration.swift"] = "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Root\"])\n"
		}
		return [
			ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContentByFilePath: [
				"FeatTypes.swift": lazyValueBelowCalledRootFeatureTypes(callee: twinCalledTypes, place: place, receivesOnlyIfAvailable: false, layout: layout),
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: appFiles, dependencies: ["Feat"]),
		]
	}

	/// `reenteringCallModules`’ types in one module, `Root` a root: what inline builds.
	private static func reenteringCallInlineModules(rootLog: String, fillLog: String, place: CalledMockPlace, redeclaredAboveCall: Bool = false) -> [ModuleFixture] {
		[
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"AppTypes.swift": lazyValueBelowCalledRootFeatureTypes(callee: "@Instantiable", place: place, receivesOnlyIfAvailable: false, layout: .belowRoot) + """


				\(reenteringFill(fillLog: fillLog, place: place, redeclaredAboveCall: redeclaredAboveCall))

				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(log: \(rootLog), f: F) {
				        self.log = log
				        self.f = f
				    }

				    @Instantiated public let log: \(rootLog)
				    @Instantiated public let f: F
				}
				""",
			]),
		]
	}

	/// `Live`, which fills the place, receives `log: fillLog` and builds `F` again: itself, or, where `redeclaredAboveCall`,
	/// through `M`, which also instantiates a `log: fillLog` of its own.
	private static func reenteringFill(fillLog: String, place: CalledMockPlace, redeclaredAboveCall: Bool) -> String {
		guard redeclaredAboveCall else {
			return place.fill(receiving: "log: \(fillLog)", instantiating: ["fBuilder: Instantiator<F>"])
		}
		return place.fill(receiving: "log: \(fillLog)", instantiating: ["m: M"]) + """


		@Instantiable
		public final class M: Instantiable {
		    public init(log: \(fillLog), fBuilder: Instantiator<F>) {
		        self.log = log
		        self.fBuilder = fBuilder
		    }

		    @Instantiated public let log: \(fillLog)
		    @Instantiated public let fBuilder: Instantiator<F>
		}
		"""
	}

	/// What `Root`’s mock and inline `Root` build, whether the `Live` that fills the place holds the instance `Root`’s `log`
	/// holds (`rootInstance`), and whether the `Live` of the `F` that `Live` builds again holds it too, each `Live`’s read as
	/// `fillInstance`: for a deferred place, the `Live` its builder builds for `id` 7. Where `redeclaredAboveCall`, `M`
	/// builds `F` again, and the inner `Live` holds `M`’s instead.
	private static func reenteringCallProbes(place: CalledMockPlace, rootInstance: String, fillInstance: String, redeclaredAboveCall: Bool = false) -> [DifferentialValueProbe] {
		let live = { (f: String) in
			switch place {
			case .plain:
				"(\(f).a.api as! Live)"
			case .deferred:
				"(\(f).a.apiBuilder.instantiate(7) as! Live)"
			}
		}
		let outerLive = live("root.f")
		let caller = redeclaredAboveCall ? "\(outerLive).m" : outerLive
		let innerLive = live("\(caller).fBuilder.instantiate()")
		let (innerHolder, innerInstance) = redeclaredAboveCall ? ("M’s", "\(caller).\(fillInstance)") : ("Root’s", rootInstance)
		return [
			DifferentialValueProbe(name: "Root", expression: "Root.mock()", knownRightExpression: "Root()"),
			DifferentialValueProbe(
				name: "Live’s log is Root’s",
				expression: "{ let root = Root.mock(); return \(outerLive).\(fillInstance) === \(rootInstance) }()",
				knownRightExpression: "{ let root = Root(); return \(outerLive).\(fillInstance) === \(rootInstance) }()",
			),
			DifferentialValueProbe(
				name: "the Live of F built again holds \(innerHolder) log",
				expression: "{ let root = Root.mock(); return \(innerLive).\(fillInstance) === \(innerInstance) }()",
				knownRightExpression: "{ let root = Root(); return \(innerLive).\(fillInstance) === \(innerInstance) }()",
			),
		]
	}

	/// `F`, a seam and public mock in module `Feat` that holds no `log`, with places `api`, beneath `A`, and `api2`, beneath
	/// `B`, each a level below its root; and, where `shape` builds `F` again through another call, `G`, a seam and public
	/// mock there too, whose place `gapi` is beneath `GA`. In `App`, `Live` fills `api`, receiving `Root`’s `log: Log`;
	/// `Live2` fills `api2`, receiving `log` as `shape` says, and builds `F` again, itself or through `G`, whose place
	/// `LiveG` fills by building `F`. `Root` holds `log` as `shape` says. `caller` decides `Root`’s attribute, or that `App`
	/// lists it in `additionalMocksToGenerate`.
	private static func reenteredFunctionModules(caller: CallingMockCallerKind, shape: ReenteredFunctionReadShape) -> [ModuleFixture] {
		var appFiles = [
			"AppTypes.swift": "import Feat\nimport SafeDI\n\n" + reenteredFunctionAppTypes(shape: shape, rootAttribute: caller.attribute(listed: "@Instantiable(isRoot: true)")),
		]
		if caller == .listed {
			appFiles["SafeDIConfiguration.swift"] = "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Root\"])\n"
		}
		return [
			ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContentByFilePath: ["FeatTypes.swift": "import SafeDI\n\n" + reenteredFunctionFeatureTypes(shape: shape, callee: twinCalledTypes)]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: appFiles, dependencies: ["Feat"]),
		]
	}

	/// `reenteredFunctionModules`’ types in one module, `Root` a root: what inline builds.
	private static func reenteredFunctionInlineModules(shape: ReenteredFunctionReadShape) -> [ModuleFixture] {
		var types = "import SafeDI\n\n"
		types += reenteredFunctionFeatureTypes(shape: shape, callee: "@Instantiable")
		types += "\n\n"
		types += reenteredFunctionAppTypes(shape: shape, rootAttribute: "@Instantiable(isRoot: true)")
		return [ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: ["AppTypes.swift": types])]
	}

	/// `F`, declared with `callee`, the types its tree builds, and, where `shape` builds `F` again through another call, `G`,
	/// declared with `callee` too.
	private static func reenteredFunctionFeatureTypes(shape: ReenteredFunctionReadShape, callee: String) -> String {
		var types = """
		public protocol Api {}

		public protocol Api2 {}

		@Instantiable
		public final class Log: Instantiable, Sendable {
		    public init() {}
		}

		@Instantiable
		public final class A: Instantiable {
		    init(api: any Api) {
		        self.api = api
		    }

		    @Instantiated public let api: any Api
		}

		@Instantiable
		public final class B: Instantiable {
		    init(api2: any Api2) {
		        self.api2 = api2
		    }

		    @Instantiated public let api2: any Api2
		}

		\(callee)
		public final class F: Instantiable {
		    public init(a: A, b: B) {
		        self.a = a
		        self.b = b
		    }

		    @Instantiated public let a: A
		    @Instantiated public let b: B
		}
		"""
		if shape.reentry == .throughOtherCall {
			types += """


			public protocol GApi {}

			@Instantiable
			public final class GA: Instantiable {
			    init(gapi: any GApi) {
			        self.gapi = gapi
			    }

			    @Instantiated public let gapi: any GApi
			}

			\(callee)
			public final class G: Instantiable {
			    public init(ga: GA) {
			        self.ga = ga
			    }

			    @Instantiated public let ga: GA
			}
			"""
		}
		return types
	}

	/// `Live`, `Live2`, `LiveG` where `shape` builds `F` again through `G`, `Nav` where it builds `F` again through a child
	/// of `Live2`, and `Root`, declared with `rootAttribute`.
	private static func reenteredFunctionAppTypes(shape: ReenteredFunctionReadShape, rootAttribute: String) -> String {
		let builtAgain = shape.reentry == .throughOtherCall ? "G" : "F"
		let liveLog = shape.liveReadsLogOnlyIfAvailable ? "Log?" : "Log"
		let liveReceive = shape.liveReadsLogOnlyIfAvailable ? "@Received(onlyIfAvailable: true)" : "@Received"
		var live2Parameters = [String]()
		var live2Assignments = [String]()
		var live2Declarations = [String]()
		if shape.fillReadsLogOnlyIfAvailable {
			live2Parameters.append("log: Log?")
			live2Assignments.append("self.log = log")
			live2Declarations.append("@Received(onlyIfAvailable: true) public let log: Log?")
		}
		if shape.reentry == .throughChild {
			live2Parameters.append("nav: Nav")
			live2Assignments.append("self.nav = nav")
			live2Declarations.append("@Instantiated public let nav: Nav")
		} else {
			live2Parameters.append("builder: Instantiator<\(builtAgain)>")
			live2Assignments.append("self.builder = builder")
			live2Declarations.append("@Instantiated public let builder: Instantiator<\(builtAgain)>")
		}
		var types = """
		@Instantiable(fulfillingAdditionalTypes: [Api.self])
		public final class Live: Api, Instantiable {
		    public init(log: \(liveLog)) {
		        self.log = log
		    }

		    \(liveReceive) public let log: \(liveLog)
		}

		@Instantiable(fulfillingAdditionalTypes: [Api2.self])
		public final class Live2: Api2, Instantiable {
		    public init(\(live2Parameters.joined(separator: ", "))) {
		\(live2Assignments.map { "        \($0)" }.joined(separator: "\n"))
		    }

		\(live2Declarations.map { "    \($0)" }.joined(separator: "\n"))
		}
		"""
		switch shape.reentry {
		case .direct:
			break
		case .throughOtherCall:
			types += """


			@Instantiable(fulfillingAdditionalTypes: [GApi.self])
			public final class LiveG: GApi, Instantiable {
			    public init(f: F) {
			        self.f = f
			    }

			    @Instantiated public let f: F
			}
			"""
		case .throughChild:
			types += """


			@Instantiable
			public final class Nav: Instantiable {
			    public init(builder: Instantiator<F>) {
			        self.builder = builder
			    }

			    @Instantiated public let builder: Instantiator<F>
			}
			"""
		}
		types += """


		\(rootAttribute)
		public final class Root: Instantiable {
		    public init(log: \(shape.rootLog), f: F) {
		        self.log = log
		        self.f = f
		    }

		    @Instantiated public let log: \(shape.rootLog)
		    @Instantiated public let f: F
		}
		"""
		return types
	}

	/// What `Root`’s mock and inline `Root` build, and whether the `Live` of `Root`’s `F`, and the `Live` of the `F` its
	/// `Live2` builds again, hold the instance `Root`’s `log` holds; where `Live2` reads `log`, whether each `Live2` does too.
	private static func reenteredFunctionProbes(shape: ReenteredFunctionReadShape) -> [DifferentialValueProbe] {
		let rootInstance = shape.rootWrapper == nil ? "root.log" : "root.log.instance"
		let outerLive2 = "(root.f.b.api2 as! Live2)"
		let builtAgain = switch shape.reentry {
		case .direct:
			"\(outerLive2).builder.instantiate()"
		case .throughChild:
			"\(outerLive2).nav.builder.instantiate()"
		case .throughOtherCall:
			"(\(outerLive2).builder.instantiate().ga.gapi as! LiveG).f"
		}
		var holders = [
			("Live", "(root.f.a.api as! Live)"),
			("the Live of F built again", "(\(builtAgain).a.api as! Live)"),
		]
		if shape.fillReadsLogOnlyIfAvailable {
			holders.append(("Live2", outerLive2))
			holders.append(("the Live2 of F built again", "(\(builtAgain).b.api2 as! Live2)"))
		}
		var probes = [DifferentialValueProbe(name: "Root", expression: "Root.mock()", knownRightExpression: "Root()")]
		for (name, holder) in holders {
			probes.append(DifferentialValueProbe(
				name: "\(name) holds Root’s log",
				expression: "{ let root = Root.mock(); return \(holder).log === \(rootInstance) }()",
				knownRightExpression: "{ let root = Root(); return \(holder).log === \(rootInstance) }()",
			))
		}
		return probes
	}

	/// `F`, a seam and public mock in module `Feat` declared with `callee`, holds a copy of `log` through its child `Z`, which
	/// receives it by value or only if available as `shape` says, and places `api`, beneath `A` (or beneath `A2`, beneath
	/// `A`, where the place is two levels below the root), and `api2`, beneath `B`; and, where `shape` builds `F` again
	/// through another call, `G`, a seam and public mock there too, whose place `gapi` is beneath `GA`. Where `shape` adds a
	/// second label, `Session` too, which `Z` receives.
	private static func redeclaredValueFeatureTypes(shape: RedeclaredValueShape, callee: String) -> String {
		let zLog = shape.copyIsOptional ? "Log?" : "Log"
		let zReceive = shape.copyIsOptional ? "@Received(onlyIfAvailable: true)" : "@Received"
		var zParameters = ["log: \(zLog)"]
		var zAssignments = ["self.log = log"]
		var zDeclarations = ["\(zReceive) public let log: \(zLog)"]
		var types = """
		public protocol Api {}

		public protocol Api2 {}

		@Instantiable
		public final class Log: Instantiable, Sendable {
		    public init() {}
		}
		"""
		if shape.neighbour == .secondLabel {
			zParameters.append("session: Session")
			zAssignments.append("self.session = session")
			zDeclarations.append("@Received public let session: Session")
			types += """


			@Instantiable
			public final class Session: Instantiable, Sendable {
			    public init() {}
			}
			"""
		}
		types += """


		@Instantiable
		public final class Z: Instantiable {
		    init(\(zParameters.joined(separator: ", "))) {
		\(zAssignments.map { "        \($0)" }.joined(separator: "\n"))
		    }

		\(zDeclarations.map { "    \($0)" }.joined(separator: "\n"))
		}
		"""
		if shape.neighbour == .placeTwoLevelsBelowRoot {
			types += """


			@Instantiable
			public final class A2: Instantiable {
			    init(api: any Api) {
			        self.api = api
			    }

			    @Instantiated public let api: any Api
			}

			@Instantiable
			public final class A: Instantiable {
			    init(a2: A2) {
			        self.a2 = a2
			    }

			    @Instantiated public let a2: A2
			}
			"""
		} else {
			types += """


			@Instantiable
			public final class A: Instantiable {
			    init(api: any Api) {
			        self.api = api
			    }

			    @Instantiated public let api: any Api
			}
			"""
		}
		types += """


		@Instantiable
		public final class B: Instantiable {
		    init(api2: any Api2) {
		        self.api2 = api2
		    }

		    @Instantiated public let api2: any Api2
		}

		\(callee)
		public final class F: Instantiable {
		    public init(a: A, b: B, z: Z) {
		        self.a = a
		        self.b = b
		        self.z = z
		    }

		    @Instantiated public let a: A
		    @Instantiated public let b: B
		    @Instantiated public let z: Z
		}
		"""
		if shape.reentry == .throughOtherCall {
			types += """


			public protocol GApi {}

			@Instantiable
			public final class GA: Instantiable {
			    init(gapi: any GApi) {
			        self.gapi = gapi
			    }

			    @Instantiated public let gapi: any GApi
			}

			\(callee)
			public final class G: Instantiable {
			    public init(ga: GA) {
			        self.ga = ga
			    }

			    @Instantiated public let ga: GA
			}
			"""
		}
		return types
	}

	/// `Live`, which fills `api` and receives `log` by value or only if available (and `session`, where `shape` adds it);
	/// `Live2`, which fills `api2`, instantiates a `log` of its own and builds `F` again, itself, through its child `Nav`, or
	/// through `G`, whose place `LiveG` fills by building `F`; and `Root`, a root that generates its mock, which holds `log`
	/// as `shape` says and `F`, or, where `shape` adds it, `Mid`, which instantiates a `log` of its own and `F`.
	private static func redeclaredValueAppTypes(shape: RedeclaredValueShape) -> String {
		let liveLog = shape.liveReadsLogOnlyIfAvailable ? "Log?" : "Log"
		let liveReceive = shape.liveReadsLogOnlyIfAvailable ? "@Received(onlyIfAvailable: true)" : "@Received"
		var liveParameters = ["log: \(liveLog)"]
		var liveAssignments = ["self.log = log"]
		var liveDeclarations = ["\(liveReceive) public let log: \(liveLog)"]
		if shape.neighbour == .secondLabel {
			liveParameters.append("session: Session")
			liveAssignments.append("self.session = session")
			liveDeclarations.append("@Received public let session: Session")
		}
		let builtAgain = shape.reentry == .throughOtherCall ? "G" : "F"
		let live2Builder = shape.reentry == .throughChild ? ("nav", "Nav") : ("builder", "Instantiator<\(builtAgain)>")
		var types = """
		@Instantiable(fulfillingAdditionalTypes: [Api.self])
		public final class Live: Api, Instantiable {
		    public init(\(liveParameters.joined(separator: ", "))) {
		\(liveAssignments.map { "        \($0)" }.joined(separator: "\n"))
		    }

		\(liveDeclarations.map { "    \($0)" }.joined(separator: "\n"))
		}

		@Instantiable(fulfillingAdditionalTypes: [Api2.self])
		public final class Live2: Api2, Instantiable {
		    public init(log: Log, \(live2Builder.0): \(live2Builder.1)) {
		        self.log = log
		        self.\(live2Builder.0) = \(live2Builder.0)
		    }

		    @Instantiated public let log: Log
		    @Instantiated public let \(live2Builder.0): \(live2Builder.1)
		}
		"""
		switch shape.reentry {
		case .direct:
			break
		case .throughChild:
			types += """


			@Instantiable
			public final class Nav: Instantiable {
			    public init(builder: Instantiator<F>) {
			        self.builder = builder
			    }

			    @Instantiated public let builder: Instantiator<F>
			}
			"""
		case .throughOtherCall:
			types += """


			@Instantiable(fulfillingAdditionalTypes: [GApi.self])
			public final class LiveG: GApi, Instantiable {
			    public init(f: F) {
			        self.f = f
			    }

			    @Instantiated public let f: F
			}
			"""
		}
		var rootProperties = [(label: "log", type: shape.rootLog)]
		if shape.neighbour == .secondLabel {
			rootProperties.append((label: "session", type: "Session"))
		}
		if shape.neighbour == .midDeclaresValueAgain {
			rootProperties.append((label: "mid", type: "Mid"))
			types += """


			@Instantiable
			public final class Mid: Instantiable {
			    public init(log: Log, f: F) {
			        self.log = log
			        self.f = f
			    }

			    @Instantiated public let log: Log
			    @Instantiated public let f: F
			}
			"""
		} else {
			rootProperties.append((label: "f", type: "F"))
		}
		types += """


		@Instantiable(isRoot: true, generateMock: true)
		public final class Root: Instantiable {
		    public init(\(rootProperties.map { "\($0.label): \($0.type)" }.joined(separator: ", "))) {
		\(rootProperties.map { "        self.\($0.label) = \($0.label)" }.joined(separator: "\n"))
		    }

		\(rootProperties.map { "    @Instantiated public let \($0.label): \($0.type)" }.joined(separator: "\n"))
		}
		"""
		return types
	}

	/// `redeclaredValueAppTypes`’ and `redeclaredValueFeatureTypes`’ modules: `Feat`, and `App`, which depends on it.
	private static func redeclaredValueModules(shape: RedeclaredValueShape) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContentByFilePath: ["FeatTypes.swift": "import SafeDI\n\n" + redeclaredValueFeatureTypes(shape: shape, callee: twinCalledTypes)]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: ["AppTypes.swift": "import Feat\nimport SafeDI\n\n" + redeclaredValueAppTypes(shape: shape)], dependencies: ["Feat"]),
		]
	}

	/// `redeclaredValueModules`’ types in one module, `F` and `G` plain types: what inline builds.
	private static func redeclaredValueInlineModules(shape: RedeclaredValueShape) -> [ModuleFixture] {
		var types = "import SafeDI\n\n"
		types += redeclaredValueFeatureTypes(shape: shape, callee: "@Instantiable")
		types += "\n\n"
		types += redeclaredValueAppTypes(shape: shape)
		return [ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: ["AppTypes.swift": types])]
	}

	/// What `Root()`, the production tree, and `Root.mock()` build, each against inline `Root()`, and whether each `Live`
	/// holds the `log` nearest it: the first `Live` the one `Root` (or `Mid`) holds, the `Live` and the copy `Z` holds of the
	/// `F` a `Live2` builds again that `Live2`’s own, two rounds deep where `shape` says so; where `shape` adds `session`,
	/// whether the re-entered `Live` holds `Root`’s.
	private static func redeclaredValueProbes(shape: RedeclaredValueShape) -> [DifferentialValueProbe] {
		let placePath = shape.neighbour == .placeTwoLevelsBelowRoot ? "a.a2.api" : "a.api"
		func builtAgain(by live2: String) -> String {
			switch shape.reentry {
			case .direct:
				"\(live2).builder.instantiate()"
			case .throughChild:
				"\(live2).nav.builder.instantiate()"
			case .throughOtherCall:
				"(\(live2).builder.instantiate().ga.gapi as! LiveG).f"
			}
		}
		let owner = shape.neighbour == .midDeclaresValueAgain ? "root.mid" : "root"
		let nearestLog = shape.neighbour == .midDeclaresValueAgain || shape.rootWrapper == nil ? "\(owner).log" : "root.log.instance"
		var checks = [
			("the first Live holds the nearest log", "(\(owner).f.\(placePath) as! Live).log === \(nearestLog)"),
			("the Live of F built again holds Live2’s log", "(again.\(placePath) as! Live).log === live2.log"),
			("the Z of F built again holds Live2’s log", "again.z.log === live2.log"),
		]
		if shape.neighbour == .secondLabel {
			checks.append(("the Live of F built again holds Root’s session", "(again.\(placePath) as! Live).session === root.session"))
		}
		if shape.neighbour == .thirdRound {
			checks.append(("the Live of F built a third time holds the second Live2’s log", "{ let live2 = again.b.api2 as! Live2; let again = \(builtAgain(by: "live2")); return (again.\(placePath) as! Live).log === live2.log }()"))
		}
		var probes = [
			DifferentialValueProbe(name: "Root()", expression: "Root()", knownRightExpression: "Root()"),
			DifferentialValueProbe(name: "Root.mock()", expression: "Root.mock()", knownRightExpression: "Root()"),
		]
		for (call, path) in [("Root()", "production"), ("Root.mock()", "mock")] {
			for (name, check) in checks {
				probes.append(DifferentialValueProbe(
					name: "\(path): \(name)",
					expression: "{ let root = \(call); let live2 = \(owner).f.b.api2 as! Live2; let again = \(builtAgain(by: "live2")); return \(check) }()",
					knownRightExpression: "{ let root = Root(); let live2 = \(owner).f.b.api2 as! Live2; let again = \(builtAgain(by: "live2")); return \(check) }()",
				))
			}
		}
		return probes
	}

	/// `Z` receives `log` only if available, as `Log?`, where `receivesOnlyIfAvailable`. `layout` says where the place is,
	/// and whether `B` declares `log` again above `A`. Where `logIsInstantiable` is `false`, `Log` is no `@Instantiable`, so
	/// nothing builds it.
	private static func lazyValueBelowCalledRootFeatureTypes(callee: String, place: CalledMockPlace, receivesOnlyIfAvailable: Bool, layout: LazyValueLayout, logIsInstantiable: Bool = true) -> String {
		let zLog = receivesOnlyIfAvailable ? "Log?" : "Log"
		let zReceive = receivesOnlyIfAvailable ? "@Received(onlyIfAvailable: true)" : "@Received"
		var a = """
		@Instantiable
		public final class A: Instantiable {
		    init(\(place.label): \(place.type)) {
		        self.\(place.label) = \(place.label)
		    }

		    \(place.attribute) public let \(place.label): \(place.type)
		}
		"""
		if case let .redeclaredBelowRoot(wrapper) = layout {
			a += """


			@Instantiable
			public final class B: Instantiable {
			    init(log: \(wrapper.name)<Log>, a: A) {
			        self.log = log
			        self.a = a
			    }

			    @Instantiated public let log: \(wrapper.name)<Log>
			    @Instantiated public let a: A
			}
			"""
		}
		let f = switch layout {
		case .belowRoot:
			"""
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
		case .redeclaredBelowRoot:
			"""
			\(callee)
			public final class F: Instantiable {
			    public init(b: B, z: Z) {
			        self.b = b
			        self.z = z
			    }

			    @Instantiated public let b: B
			    @Instantiated public let z: Z
			}
			"""
		case .atRoot:
			"""
			\(callee)
			public final class F: Instantiable {
			    public init(\(place.label): \(place.type), z: Z) {
			        self.\(place.label) = \(place.label)
			        self.z = z
			    }

			    \(place.attribute) public let \(place.label): \(place.type)
			    @Instantiated public let z: Z
			}
			"""
		}
		let log = if logIsInstantiable {
			"""
			@Instantiable
			public final class Log: Instantiable, Sendable {
			    public init() {}
			}
			"""
		} else {
			"""
			public final class Log: Sendable {
			    public init() {}
			}
			"""
		}
		return """
		import SafeDI

		public protocol Api {}

		\(log)

		\(a)

		@Instantiable
		public final class Z: Instantiable {
		    init(log: \(zLog)) {
		        self.log = log
		    }

		    \(zReceive) public let log: \(zLog)
		}

		\(f)
		"""
	}

	/// What `Root`’s mock and inline `Root` build, and whether the `Live` that fills the place holds the instance `Root`’s
	/// `log` holds: for a deferred place, the `Live` its builder builds for `id` 7.
	/// Where `layout` has `B` declare `log` again, whether that `Live` holds the instance `B`’s `log` holds instead.
	private static func lazyValueBelowCalledRootProbes(place: CalledMockPlace, layout: LazyValueLayout = .belowRoot) -> [DifferentialValueProbe] {
		let owner = switch layout {
		case .belowRoot:
			"root.f.a"
		case .atRoot:
			"root.f"
		case .redeclaredBelowRoot:
			"root.f.b.a"
		}
		let live = switch place {
		case .plain:
			"(\(owner).api as! Live)"
		case .deferred:
			"(\(owner).apiBuilder.instantiate(7) as! Live)"
		}
		let (holder, holderLog) = switch layout {
		case .belowRoot, .atRoot:
			("Root’s", "root.log")
		case .redeclaredBelowRoot:
			("B’s", "root.f.b.log")
		}
		return [
			DifferentialValueProbe(name: "Root", expression: "Root.mock()", knownRightExpression: "Root()"),
			DifferentialValueProbe(
				name: "Live’s log is \(holder)",
				expression: "{ let root = Root.mock(); return \(live).log.instance === \(holderLog).instance }()",
				knownRightExpression: "{ let root = Root(); return \(live).log.instance === \(holderLog).instance }()",
			),
		]
	}

	/// `lazyValueBelowCalledRootModules`’ feature module, with `App`’s `Root` instantiating `log` in `wrapper`’s form and
	/// `Mid`, which builds `F`, as `chain` says. `caller` decides the mocked type’s attribute, or that `App` lists it in
	/// `additionalMocksToGenerate`.
	private static func lazyValueThroughMidModules(chain: LazyValueChain, caller: CallingMockCallerKind, wrapper: CallerLazyWrapper) -> [ModuleFixture] {
		let (mockedType, rootAttribute, midAttribute) = if chain.mocksMid {
			("Mid", "@Instantiable(isRoot: true)", caller.attribute(listed: "@Instantiable"))
		} else {
			("Root", caller.attribute(listed: "@Instantiable(isRoot: true)"), "@Instantiable")
		}
		var appFiles = [
			"AppTypes.swift": "import Feat\nimport SafeDI\n\n" + lazyValueThroughMidAppTypes(chain: chain, rootAttribute: rootAttribute, midAttribute: midAttribute, wrapper: wrapper),
		]
		if caller == .listed {
			appFiles["SafeDIConfiguration.swift"] = "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"\(mockedType)\"])\n"
		}
		return [
			ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContentByFilePath: [
				"FeatTypes.swift": lazyValueBelowCalledRootFeatureTypes(callee: twinCalledTypes, place: .plain, receivesOnlyIfAvailable: false, layout: .belowRoot),
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: appFiles, dependencies: ["Feat"]),
		]
	}

	/// `lazyValueThroughMidModules`’ types in one module, `Root` a root: what inline builds.
	private static func lazyValueThroughMidInlineModules(chain: LazyValueChain, wrapper: CallerLazyWrapper) -> [ModuleFixture] {
		var types = lazyValueBelowCalledRootFeatureTypes(callee: "@Instantiable", place: .plain, receivesOnlyIfAvailable: false, layout: .belowRoot)
		types += "\n\n"
		types += lazyValueThroughMidAppTypes(chain: chain, rootAttribute: "@Instantiable(isRoot: true)", midAttribute: "@Instantiable", wrapper: wrapper)
		return [ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: ["AppTypes.swift": types])]
	}

	/// `Live`, which fills `F`’s place and receives `log` in `wrapper`’s form; `Root`, which instantiates it, as `appLog`
	/// where `Mid` receives it under an alias, and `Mid`; and `Mid`, which builds `F`, receiving `log` as `chain` says.
	private static func lazyValueThroughMidAppTypes(chain: LazyValueChain, rootAttribute: String, midAttribute: String, wrapper: CallerLazyWrapper) -> String {
		let rootLabel = chain == .unmockedMidReceivingValueUnderAlias ? "appLog" : "log"
		let midReceive: String? = switch chain {
		case .mockedMidBuildingCallBesideNothing, .unmockedMid:
			nil
		case .mockedMidReceivingValue:
			"@Received public let log: \(wrapper.name)<Log>"
		case .unmockedMidReceivingValueUnderAlias:
			"@Received(fulfilledByDependencyNamed: \"appLog\", ofType: \(wrapper.name)<Log>.self) public let log: \(wrapper.name)<Log>"
		}
		let mid = if let midReceive {
			"""
			\(midAttribute)
			public final class Mid: Instantiable {
			    public init(log: \(wrapper.name)<Log>, f: F) {
			        self.log = log
			        self.f = f
			    }

			    \(midReceive)
			    @Instantiated public let f: F
			}
			"""
		} else {
			"""
			\(midAttribute)
			public final class Mid: Instantiable {
			    public init(f: F) {
			        self.f = f
			    }

			    @Instantiated public let f: F
			}
			"""
		}
		return """
		\(CalledMockPlace.plain.fill(receiving: "log: \(wrapper.name)<Log>"))

		\(rootAttribute)
		public final class Root: Instantiable {
		    public init(\(rootLabel): \(wrapper.name)<Log>, mid: Mid) {
		        self.\(rootLabel) = \(rootLabel)
		        self.mid = mid
		    }

		    @Instantiated public let \(rootLabel): \(wrapper.name)<Log>
		    @Instantiated public let mid: Mid
		}

		\(mid)
		"""
	}

	/// What the mocked type’s mock and inline build; whether the `Live` that fills `F`’s place holds the instance `F`’s `Z`
	/// holds; and, where the mocked type or `Mid` beneath it holds `log`, whether `Live` holds that wrapper.
	private static func lazyValueThroughMidProbes(chain: LazyValueChain) -> [DifferentialValueProbe] {
		let (name, mock, inline, mid) = if chain.mocksMid {
			("Mid", "Mid.mock()", "Root().mid", "subject")
		} else {
			("Root", "Root.mock()", "Root()", "subject.mid")
		}
		let live = "(\(mid).f.a.api as! Live)"
		var probes = [
			DifferentialValueProbe(name: name, expression: mock, knownRightExpression: inline),
			DifferentialValueProbe(
				name: "Live’s log holds Z’s instance",
				expression: "{ let subject = \(mock); return \(live).log.instance === \(mid).f.z.log }()",
				knownRightExpression: "{ let subject = \(inline); return \(live).log.instance === \(mid).f.z.log }()",
			),
		]
		let wrapperHolder: String? = switch chain {
		case .mockedMidBuildingCallBesideNothing:
			nil
		case .mockedMidReceivingValue, .unmockedMid:
			"subject.log"
		case .unmockedMidReceivingValueUnderAlias:
			"subject.appLog"
		}
		if let wrapperHolder {
			probes.append(DifferentialValueProbe(
				name: "Live’s log is \(wrapperHolder)",
				expression: "{ let subject = \(mock); return \(live).log === \(wrapperHolder) }()",
				knownRightExpression: "{ let subject = \(inline); return \(live).log === \(wrapperHolder) }()",
			))
		}
		return probes
	}

	/// `F`, a seam and public mock in module `Feat`, holds its place on its root level and `Z`, which receives `log` by value,
	/// so `F`’s mock binds `log` by value. `Live` fills the place, receives `log` in `wrapper`’s form, and instantiates
	/// `child: LiveChild`, which receives `log` by value. `Root` instantiates `log` in `wrapper`’s form, and is the calling mock
	/// `caller` says.
	private static func callersWrapperAndInstanceAtCalledRootModules(caller: CallingMockCallerKind, wrapper: CallerLazyWrapper) -> [ModuleFixture] {
		var appFiles = [
			"AppTypes.swift": "import Feat\nimport SafeDI\n\n" + callersWrapperAndInstanceAtCalledRootAppTypes(rootAttribute: caller.attribute(listed: "@Instantiable(isRoot: true)"), wrapper: wrapper),
		]
		if caller == .listed {
			appFiles["SafeDIConfiguration.swift"] = "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Root\"])\n"
		}
		return [
			ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContentByFilePath: [
				"FeatTypes.swift": lazyValueBelowCalledRootFeatureTypes(callee: twinCalledTypes, place: .plain, receivesOnlyIfAvailable: false, layout: .atRoot),
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: appFiles, dependencies: ["Feat"]),
		]
	}

	/// `callersWrapperAndInstanceAtCalledRootModules`’ types in one module, `Root` a root: what inline builds.
	private static func callersWrapperAndInstanceAtCalledRootInlineModules(wrapper: CallerLazyWrapper) -> [ModuleFixture] {
		var types = lazyValueBelowCalledRootFeatureTypes(callee: "@Instantiable", place: .plain, receivesOnlyIfAvailable: false, layout: .atRoot)
		types += "\n\n"
		types += callersWrapperAndInstanceAtCalledRootAppTypes(rootAttribute: "@Instantiable(isRoot: true)", wrapper: wrapper)
		return [ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: ["AppTypes.swift": types])]
	}

	/// `Live`, `LiveChild` and `Root` of `callersWrapperAndInstanceAtCalledRootModules`.
	private static func callersWrapperAndInstanceAtCalledRootAppTypes(rootAttribute: String, wrapper: CallerLazyWrapper) -> String {
		"""
		\(CalledMockPlace.plain.fill(receiving: "log: \(wrapper.name)<Log>", instantiating: ["child: LiveChild"]))

		@Instantiable
		public final class LiveChild: Instantiable {
		    public init(log: Log) {
		        self.log = log
		    }

		    @Received public let log: Log
		}

		\(rootAttribute)
		public final class Root: Instantiable {
		    public init(log: \(wrapper.name)<Log>, f: F) {
		        self.log = log
		        self.f = f
		    }

		    @Instantiated public let log: \(wrapper.name)<Log>
		    @Instantiated public let f: F
		}
		"""
	}

	/// What `Root`’s mock and inline `Root` build, and whether `Live` holds `Root`’s wrapper and its child, and `F`’s `Z`, the
	/// wrapper’s instance.
	private static let callersWrapperAndInstanceAtCalledRootProbes = [
		DifferentialValueProbe(name: "Root", expression: "Root.mock()", knownRightExpression: "Root()"),
		DifferentialValueProbe(
			name: "Live’s log is Root’s",
			expression: "{ let root = Root.mock(); return (root.f.api as! Live).log === root.log }()",
			knownRightExpression: "{ let root = Root(); return (root.f.api as! Live).log === root.log }()",
		),
		DifferentialValueProbe(
			name: "LiveChild’s log is Root’s instance",
			expression: "{ let root = Root.mock(); return (root.f.api as! Live).child.log === root.log.instance }()",
			knownRightExpression: "{ let root = Root(); return (root.f.api as! Live).child.log === root.log.instance }()",
		),
		DifferentialValueProbe(
			name: "Z’s log is Root’s instance",
			expression: "{ let root = Root.mock(); return root.f.z.log === root.log.instance }()",
			knownRightExpression: "{ let root = Root(); return root.f.z.log === root.log.instance }()",
		),
	]

	/// `F`, a seam and public mock in module `Feat`, holds its place below its root, beneath `A`, or on its root level, as
	/// `shape` says, and `Z`, which receives `log` by value, so `F`’s mock binds `log` by value. `Live` fills the place and
	/// receives `log` in `wrapper`’s form. `Mid`, the calling mock `caller` says, builds `F` and binds that wrapper apart from
	/// `log`, as `shape` says.
	private static func mockRootBindingModules(shape: MockRootBindingShape, caller: CallingMockCallerKind, wrapper: CallerLazyWrapper) -> [ModuleFixture] {
		var appFiles = [
			"AppTypes.swift": "import Feat\nimport SafeDI\n\n" + mockRootBindingAppTypes(shape: shape, midAttribute: caller.attribute(listed: "@Instantiable"), wrapper: wrapper),
		]
		if caller == .listed {
			appFiles["SafeDIConfiguration.swift"] = "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Mid\"])\n"
		}
		return [
			ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContentByFilePath: [
				"FeatTypes.swift": lazyValueBelowCalledRootFeatureTypes(callee: twinCalledTypes, place: .plain, receivesOnlyIfAvailable: false, layout: shape.layout, logIsInstantiable: shape.logIsInstantiable),
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: appFiles, dependencies: ["Feat"]),
		]
	}

	/// `mockRootBindingModules`’ types in one module, where `Mid`’s mock builds `F` inline: what the calling mock is compared
	/// with.
	private static func mockRootBindingInlineModules(shape: MockRootBindingShape, caller: CallingMockCallerKind, wrapper: CallerLazyWrapper) -> [ModuleFixture] {
		var types = lazyValueBelowCalledRootFeatureTypes(callee: "@Instantiable", place: .plain, receivesOnlyIfAvailable: false, layout: shape.layout, logIsInstantiable: shape.logIsInstantiable)
		types += "\n\n"
		types += mockRootBindingAppTypes(shape: shape, midAttribute: caller.attribute(listed: "@Instantiable"), wrapper: wrapper)
		var files = ["AppTypes.swift": types]
		if caller == .listed {
			files["SafeDIConfiguration.swift"] = "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Mid\"])\n"
		}
		return [ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: files)]
	}

	/// `Live`, which fills `F`’s place, and `Mid`, which builds `F`, as `shape` says.
	private static func mockRootBindingAppTypes(shape: MockRootBindingShape, midAttribute: String, wrapper: CallerLazyWrapper) -> String {
		let live = if shape.childReadsInstance {
			CalledMockPlace.plain.fill(receiving: "log: \(wrapper.name)<Log>", instantiating: ["child: LiveChild"]) + """


			@Instantiable
			public final class LiveChild: Instantiable {
			    public init(log: Log) {
			        self.log = log
			    }

			    @Received public let log: Log
			}
			"""
		} else {
			CalledMockPlace.plain.fill(receiving: "log: \(wrapper.name)<Log>")
		}
		let mid = switch shape {
		case .wrapperOfParameter, .wrapperOfParameterAndItsInstance, .wrapperOfParameterOnCalledTypesRootLevel:
			"""
			\(midAttribute)
			public final class Mid: Instantiable {
			    public init(log: \(wrapper.name)<Log>, f: F) {
			        self.log = log
			        self.f = f
			    }

			    @Received public let log: \(wrapper.name)<Log>
			    @Instantiated public let f: F
			}
			"""
		case .promotedBesideAnotherForm:
			"""
			@Instantiable
			public final class Other: Instantiable {
			    public init(log: Instantiator<Log>) {
			        self.log = log
			    }

			    @Received public let log: Instantiator<Log>
			}

			\(midAttribute)
			public final class Mid: Instantiable {
			    public init(f: F, other: Other) {
			        self.f = f
			        self.other = other
			    }

			    @Instantiated public let f: F
			    @Instantiated public let other: Other
			}
			"""
		case .promotedBesideDefaultValuedParameter:
			"""
			\(midAttribute)
			public final class Mid: Instantiable {
			    public init(f: F, log: String = "") {
			        self.f = f
			    }

			    @Instantiated public let f: F
			}
			"""
		}
		return live + "\n\n" + mid
	}

	/// What `Mid`’s calling mock and its mock built inline build, whether `Live` holds the wrapper whose instance `F`’s `Z`
	/// holds, and, as `shape` says, whether `Live` holds `Mid`’s wrapper and `LiveChild` the instance `Z` holds.
	private static func mockRootBindingProbes(shape: MockRootBindingShape, mockCall: String) -> [DifferentialValueProbe] {
		let live = shape.placeIsOnCalledTypesRootLevel ? "(mid.f.api as! Live)" : "(mid.f.a.api as! Live)"
		var probes = [DifferentialValueProbe]()
		// Where `LiveChild` reads the instance, the calling mock’s fill reads it as its wrapper’s instance, so the wrapper `Mid`’s
		// mock makes of the instance it takes has made it, where `Mid`’s mock built inline reads the instance itself: the same
		// instance, whose wrapper runs no builder of its own (`public-mock-builders.md`, “The caller’s own value”). The other
		// probes compare which instance each holds.
		if !shape.childReadsInstance {
			probes.append(DifferentialValueProbe(name: "Mid", expression: mockCall, knownRightExpression: mockCall))
		}
		probes.append(DifferentialValueProbe(
			name: "Live’s log holds Z’s instance",
			expression: "{ let mid = \(mockCall); return \(live).log.instance === mid.f.z.log }()",
			knownRightExpression: "{ let mid = \(mockCall); return \(live).log.instance === mid.f.z.log }()",
		))
		if !shape.logIsInstantiable {
			probes.append(DifferentialValueProbe(
				name: "Live’s log is Mid’s",
				expression: "{ let mid = \(mockCall); return \(live).log === mid.log }()",
				knownRightExpression: "{ let mid = \(mockCall); return \(live).log === mid.log }()",
			))
		}
		if shape.childReadsInstance {
			probes.append(DifferentialValueProbe(
				name: "LiveChild’s log is Z’s",
				expression: "{ let mid = \(mockCall); return \(live).child.log === mid.f.z.log }()",
				knownRightExpression: "{ let mid = \(mockCall); return \(live).child.log === mid.f.z.log }()",
			))
		}
		return probes
	}

	/// `F` in module `Feat`, as `lazyValueBelowCalledRootModules` declares it, and `G`, a seam and public mock there too,
	/// whose place `gapi` is a level below its root, beneath `GA`. In `App`, `LiveG` fills `G`’s place and builds `F`, whose
	/// place `Live` fills, receiving `Root`’s `log: LazilyInstantiated<Log>`. `caller` decides `Root`’s attribute, or that
	/// `App` lists it in `additionalMocksToGenerate`.
	private static func callInsideFillModules(caller: CallingMockCallerKind) -> [ModuleFixture] {
		var appFiles = [
			"AppTypes.swift": "import Feat\nimport SafeDI\n\n" + callInsideFillAppTypes(rootAttribute: caller.attribute(listed: "@Instantiable(isRoot: true)")),
		]
		if caller == .listed {
			appFiles["SafeDIConfiguration.swift"] = "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Root\"])\n"
		}
		var featureTypes = lazyValueBelowCalledRootFeatureTypes(callee: twinCalledTypes, place: .plain, receivesOnlyIfAvailable: false, layout: .belowRoot)
		featureTypes += "\n\n"
		featureTypes += callInsideFillOuterTypes(callee: twinCalledTypes)
		return [
			ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContentByFilePath: ["FeatTypes.swift": featureTypes]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: appFiles, dependencies: ["Feat"]),
		]
	}

	/// `callInsideFillModules`’ types in one module, `Root` a root: what inline builds.
	private static var callInsideFillInlineModules: [ModuleFixture] {
		var types = lazyValueBelowCalledRootFeatureTypes(callee: "@Instantiable", place: .plain, receivesOnlyIfAvailable: false, layout: .belowRoot)
		types += "\n\n"
		types += callInsideFillOuterTypes(callee: "@Instantiable")
		types += "\n\n"
		types += callInsideFillAppTypes(rootAttribute: "@Instantiable(isRoot: true)")
		return [ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: ["AppTypes.swift": types])]
	}

	/// `G`, declared with `callee`, and the types its tree builds beside `Z`.
	private static func callInsideFillOuterTypes(callee: String) -> String {
		"""
		public protocol GApi {}

		@Instantiable
		public final class GA: Instantiable {
		    init(gapi: any GApi) {
		        self.gapi = gapi
		    }

		    @Instantiated public let gapi: any GApi
		}

		\(callee)
		public final class G: Instantiable {
		    public init(ga: GA, z: Z) {
		        self.ga = ga
		        self.z = z
		    }

		    @Instantiated public let ga: GA
		    @Instantiated public let z: Z
		}
		"""
	}

	/// `Live`, `LiveG` and `Root`, declared with `rootAttribute`, of `callInsideFillModules`.
	private static func callInsideFillAppTypes(rootAttribute: String) -> String {
		"""
		\(CalledMockPlace.plain.fill(receiving: "log: LazilyInstantiated<Log>"))

		@Instantiable(fulfillingAdditionalTypes: [GApi.self])
		public final class LiveG: GApi, Instantiable {
		    public init(f: F) {
		        self.f = f
		    }

		    @Instantiated public let f: F
		}

		\(rootAttribute)
		public final class Root: Instantiable {
		    public init(log: LazilyInstantiated<Log>, g: G) {
		        self.log = log
		        self.g = g
		    }

		    @Instantiated public let log: LazilyInstantiated<Log>
		    @Instantiated public let g: G
		}
		"""
	}

	/// The adopter’s shape with `F` also holding `aBuilder: SendableInstantiator<A>`, so `F` builds `A`’s place below its root
	/// both in plain code and inside the instantiator’s `@Sendable` function, outside which `F`’s mock binds `log`. `Live`
	/// fills both places and receives `Root`’s `log: SendableLazilyInstantiated<Log>`. `caller` decides `Root`’s attribute,
	/// or that `App` lists it in `additionalMocksToGenerate`.
	private static func sendableInstantiatorPlaceModules(caller: CallingMockCallerKind, receivesOnlyIfAvailable: Bool = false) -> [ModuleFixture] {
		var appFiles = [
			"AppTypes.swift": "import Feat\nimport SafeDI\n\n" + sendableInstantiatorPlaceAppTypes(rootAttribute: caller.attribute(listed: "@Instantiable(isRoot: true)")),
		]
		if caller == .listed {
			appFiles["SafeDIConfiguration.swift"] = "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Root\"])\n"
		}
		return [
			ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContentByFilePath: ["FeatTypes.swift": sendableInstantiatorPlaceFeatureTypes(callee: twinCalledTypes, receivesOnlyIfAvailable: receivesOnlyIfAvailable)]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: appFiles, dependencies: ["Feat"]),
		]
	}

	/// `sendableInstantiatorPlaceModules`’ types in one module, `Root` a root: what inline builds.
	private static var sendableInstantiatorPlaceInlineModules: [ModuleFixture] {
		sendableInstantiatorPlaceInlineModules(receivesOnlyIfAvailable: false)
	}

	/// `sendableInstantiatorPlaceModules`’ types in one module, `Root` a root: what inline builds.
	private static func sendableInstantiatorPlaceInlineModules(receivesOnlyIfAvailable: Bool) -> [ModuleFixture] {
		var types = sendableInstantiatorPlaceFeatureTypes(callee: "@Instantiable", receivesOnlyIfAvailable: receivesOnlyIfAvailable)
		types += "\n\n"
		types += sendableInstantiatorPlaceAppTypes(rootAttribute: "@Instantiable(isRoot: true)")
		return [ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: ["AppTypes.swift": types])]
	}

	/// `F`, declared with `callee`, and the types its tree builds, of `sendableInstantiatorPlaceModules`. `Z` receives `log`
	/// only if available, as `Log?`, where `receivesOnlyIfAvailable`.
	private static func sendableInstantiatorPlaceFeatureTypes(callee: String, receivesOnlyIfAvailable: Bool = false) -> String {
		let zLog = receivesOnlyIfAvailable ? "Log?" : "Log"
		let zReceive = receivesOnlyIfAvailable ? "@Received(onlyIfAvailable: true)" : "@Received"
		return """
		public protocol Api: Sendable {}

		@Instantiable
		public final class Log: Instantiable, Sendable {
		    public init() {}
		}

		@Instantiable
		public final class A: Instantiable, Sendable {
		    init(api: any Api) {
		        self.api = api
		    }

		    @Instantiated public let api: any Api
		}

		@Instantiable
		public final class Z: Instantiable, Sendable {
		    init(log: \(zLog)) {
		        self.log = log
		    }

		    \(zReceive) public let log: \(zLog)
		}

		\(callee)
		public final class F: Instantiable, Sendable {
		    public init(a: A, aBuilder: SendableInstantiator<A>, z: Z) {
		        self.a = a
		        self.aBuilder = aBuilder
		        self.z = z
		    }

		    @Instantiated public let a: A
		    @Instantiated public let aBuilder: SendableInstantiator<A>
		    @Instantiated public let z: Z
		}
		"""
	}

	/// `Live` and `Root`, declared with `rootAttribute`, of `sendableInstantiatorPlaceModules`.
	private static func sendableInstantiatorPlaceAppTypes(rootAttribute: String) -> String {
		"""
		@Instantiable(fulfillingAdditionalTypes: [Api.self])
		public final class Live: Api, Sendable, Instantiable {
		    public init(log: SendableLazilyInstantiated<Log>) {
		        self.log = log
		    }

		    @Received public let log: SendableLazilyInstantiated<Log>
		}

		\(rootAttribute)
		public final class Root: Instantiable {
		    public init(log: SendableLazilyInstantiated<Log>, f: F) {
		        self.log = log
		        self.f = f
		    }

		    @Instantiated public let log: SendableLazilyInstantiated<Log>
		    @Instantiated public let f: F
		}
		"""
	}

	/// The adopter’s shape with a second place whose fill builds the called type again: `F` builds `A`, whose place `api`
	/// `Live` fills, receiving `Root`’s `log` in `pair`’s wrapper, and `Z`, which receives `log`, so `F`’s mock binds `log` by
	/// value. `LiveOther` fills the place `other`, which `B`, beside `A`, holds, or, where `layout` says so, `A` beside
	/// `api`, and reads no `log`: it instantiates `fBuilder` in `pair`’s instantiator, or its child `OtherChild` does.
	/// `caller` decides `Root`’s attribute, or that `App` lists it in `additionalMocksToGenerate`.
	private static func otherFillReentersModules(caller: CallingMockCallerKind, pair: ReenteringWrapperPair, layout: ReenteringOtherPlaceLayout) -> [ModuleFixture] {
		var appFiles = [
			"AppTypes.swift": "import Feat\nimport SafeDI\n\n" + otherFillReentersAppTypes(rootAttribute: caller.attribute(listed: "@Instantiable(isRoot: true)"), pair: pair, layout: layout),
		]
		if caller == .listed {
			appFiles["SafeDIConfiguration.swift"] = "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Root\"])\n"
		}
		return [
			ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContentByFilePath: ["FeatTypes.swift": otherFillReentersFeatureTypes(callee: twinCalledTypes, layout: layout)]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: appFiles, dependencies: ["Feat"]),
		]
	}

	/// `F`, declared with `callee`, and the types its tree builds, of `otherFillReentersModules`.
	private static func otherFillReentersFeatureTypes(callee: String, layout: ReenteringOtherPlaceLayout) -> String {
		var types = """
		import SafeDI

		public protocol Api {}

		public protocol Other {}

		@Instantiable
		public final class Log: Instantiable, Sendable {
		    public init() {}
		}

		@Instantiable
		public final class Z: Instantiable {
		    init(log: Log) {
		        self.log = log
		    }

		    @Received public let log: Log
		}


		"""
		switch layout {
		case .otherLevel, .childOfOtherFill:
			types += """
			@Instantiable
			public final class A: Instantiable {
			    init(api: any Api) {
			        self.api = api
			    }

			    @Instantiated public let api: any Api
			}

			@Instantiable
			public final class B: Instantiable {
			    init(other: any Other) {
			        self.other = other
			    }

			    @Instantiated public let other: any Other
			}

			\(callee)
			public final class F: Instantiable {
			    public init(a: A, b: B, z: Z) {
			        self.a = a
			        self.b = b
			        self.z = z
			    }

			    @Instantiated public let a: A
			    @Instantiated public let b: B
			    @Instantiated public let z: Z
			}
			"""
		case .placesLevel:
			types += """
			@Instantiable
			public final class A: Instantiable {
			    init(api: any Api, other: any Other) {
			        self.api = api
			        self.other = other
			    }

			    @Instantiated public let api: any Api
			    @Instantiated public let other: any Other
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
		return types
	}

	/// `Live`, `LiveOther`, `OtherChild` where `layout` has it build `F` again, and `Root`, declared with `rootAttribute`, of
	/// `otherFillReentersModules`.
	private static func otherFillReentersAppTypes(rootAttribute: String, pair: ReenteringWrapperPair, layout: ReenteringOtherPlaceLayout) -> String {
		let log = "\(pair.wrapper.name)<Log>"
		let fBuilder = "\(pair.instantiator)<F>"
		var types = """
		@Instantiable(fulfillingAdditionalTypes: [Api.self])
		public final class Live: Api, Instantiable {
		    public init(log: \(log)) {
		        self.log = log
		    }

		    @Received public let log: \(log)
		}


		"""
		switch layout {
		case .otherLevel, .placesLevel:
			types += """
			@Instantiable(fulfillingAdditionalTypes: [Other.self])
			public final class LiveOther: Other, Instantiable {
			    public init(fBuilder: \(fBuilder)) {
			        self.fBuilder = fBuilder
			    }

			    @Instantiated public let fBuilder: \(fBuilder)
			}
			"""
		case .childOfOtherFill:
			types += """
			@Instantiable(fulfillingAdditionalTypes: [Other.self])
			public final class LiveOther: Other, Instantiable {
			    public init(child: OtherChild) {
			        self.child = child
			    }

			    @Instantiated public let child: OtherChild
			}

			@Instantiable
			public final class OtherChild: Instantiable {
			    public init(fBuilder: \(fBuilder)) {
			        self.fBuilder = fBuilder
			    }

			    @Instantiated public let fBuilder: \(fBuilder)
			}
			"""
		}
		types += """


		\(rootAttribute)
		public final class Root: Instantiable {
		    public init(log: \(log), f: F) {
		        self.log = log
		        self.f = f
		    }

		    @Instantiated public let log: \(log)
		    @Instantiated public let f: F
		}
		"""
		return types
	}

	/// The adopter’s shape with its place on the called type’s root level and a second place below it whose fill builds the
	/// called type again: `F` holds `api`, which `Live` fills, receiving `Root`’s `log` in `pair`’s wrapper; `B`, whose place
	/// `other` `LiveOther` fills, reading no `log` and instantiating `fBuilder` in `pair`’s instantiator; and `Z`, which
	/// receives `log`, so `F`’s mock binds `log` by value. `variation` changes one thing of that shape. `caller` decides
	/// `Root`’s attribute, or that `App` lists it in `additionalMocksToGenerate`.
	private static func rootLevelReaderModules(caller: CallingMockCallerKind, pair: ReenteringWrapperPair, variation: RootLevelReaderVariation) -> [ModuleFixture] {
		var appFiles = [
			"AppTypes.swift": "import Feat\nimport SafeDI\n\n" + rootLevelReaderAppTypes(rootAttribute: caller.attribute(listed: "@Instantiable(isRoot: true)"), pair: pair, variation: variation),
		]
		if caller == .listed {
			appFiles["SafeDIConfiguration.swift"] = "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Root\"])\n"
		}
		return [
			ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContentByFilePath: ["FeatTypes.swift": rootLevelReaderFeatureTypes(wrapper: pair.wrapper, variation: variation)]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: appFiles, dependencies: ["Feat"]),
		]
	}

	/// `F`, a seam and public mock, and the types its tree builds, of `rootLevelReaderModules`. Where `variation` says so, `B`
	/// also instantiates a `log` of its own in `wrapper`’s form, above `other`.
	private static func rootLevelReaderFeatureTypes(wrapper: CallerLazyWrapper, variation: RootLevelReaderVariation) -> String {
		var zLog = "Log"
		var zReceive = "@Received"
		if variation == .receivedOnlyIfAvailable {
			zLog = "Log?"
			zReceive = "@Received(onlyIfAvailable: true)"
		}
		var place = (label: "api", type: "any Api", attribute: "@Instantiated")
		if variation == .erasedPlace {
			place = (label: "apiBuilder", type: "ErasedInstantiator<(), any Api>", attribute: "@Instantiated(fulfilledByType: \"Api\")")
		}
		var holder = (label: "b", type: "B")
		var b = """
		@Instantiable
		public final class B: Instantiable {
		    init(other: any Other) {
		        self.other = other
		    }

		    @Instantiated public let other: any Other
		}
		"""
		if variation == .levelDeclaresValueAgainAboveOtherPlace {
			b = """
			@Instantiable
			public final class B: Instantiable {
			    init(log: \(wrapper.name)<Log>, other: any Other) {
			        self.log = log
			        self.other = other
			    }

			    @Instantiated public let log: \(wrapper.name)<Log>
			    @Instantiated public let other: any Other
			}
			"""
		}
		var types = """
		import SafeDI

		public protocol Api {}

		public protocol Other {}

		@Instantiable
		public final class Log: Instantiable, Sendable {
		    public init() {}
		}

		@Instantiable
		public final class Z: Instantiable {
		    init(log: \(zLog)) {
		        self.log = log
		    }

		    \(zReceive) public let log: \(zLog)
		}

		\(b)


		"""
		if variation == .otherPlaceTwoLevelsDown {
			holder = (label: "bb", type: "BB")
			types += """
			@Instantiable
			public final class BB: Instantiable {
			    init(b: B) {
			        self.b = b
			    }

			    @Instantiated public let b: B
			}


			"""
		}
		types += """
		\(twinCalledTypes)
		public final class F: Instantiable {
		    public init(\(place.label): \(place.type), \(holder.label): \(holder.type), z: Z) {
		        self.\(place.label) = \(place.label)
		        self.\(holder.label) = \(holder.label)
		        self.z = z
		    }

		    \(place.attribute) public let \(place.label): \(place.type)
		    @Instantiated public let \(holder.label): \(holder.type)
		    @Instantiated public let z: Z
		}
		"""
		return types
	}

	/// `Live`, `LiveOther`, `Mid` where `variation` puts it between `Root` and `F`, and `Root`, declared with
	/// `rootAttribute`, of `rootLevelReaderModules`.
	private static func rootLevelReaderAppTypes(rootAttribute: String, pair: ReenteringWrapperPair, variation: RootLevelReaderVariation) -> String {
		let log = "\(pair.wrapper.name)<Log>"
		let fBuilder = "\(pair.instantiator)<F>"
		var rootHeld = (label: "f", type: "F")
		var types = """
		@Instantiable(fulfillingAdditionalTypes: [Api.self])
		public final class Live: Api, Instantiable {
		    public init(log: \(log)) {
		        self.log = log
		    }

		    @Received public let log: \(log)
		}

		@Instantiable(fulfillingAdditionalTypes: [Other.self])
		public final class LiveOther: Other, Instantiable {
		    public init(fBuilder: \(fBuilder)) {
		        self.fBuilder = fBuilder
		    }

		    @Instantiated public let fBuilder: \(fBuilder)
		}


		"""
		if variation == .mockedTypeBetween {
			rootHeld = (label: "mid", type: "Mid")
			types += """
			@Instantiable(generateMock: true)
			public final class Mid: Instantiable {
			    public init(f: F) {
			        self.f = f
			    }

			    @Instantiated public let f: F
			}


			"""
		}
		types += """
		\(rootAttribute)
		public final class Root: Instantiable {
		    public init(log: \(log), \(rootHeld.label): \(rootHeld.type)) {
		        self.log = log
		        self.\(rootHeld.label) = \(rootHeld.label)
		    }

		    @Instantiated public let log: \(log)
		    @Instantiated public let \(rootHeld.label): \(rootHeld.type)
		}
		"""
		return types
	}

	/// A place re-entered through another module’s public mock: `Page`, a public mock in `Core`, holds the place `service`;
	/// `Book`, a public mock in `Mid`, holds `pageBuilder: Instantiator<Page>`, so its mock passes `Page`’s place up; and
	/// `DefaultService`, in `App`, fills `service`, reading the `LazilyInstantiated<Token>` the caller `Screen` instantiates
	/// and building `Book`.
	private static func crossCallLazyReentryModules(caller: CallingMockCaller) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "Core", swiftFileContentByFilePath: ["CoreTypes.swift": """
			import SafeDI

			public protocol Service: AnyObject {}

			@Instantiable(generateMock: .public)
			public final class Page: Instantiable {
			    init(service: any Service) { self.service = service }
			    @Instantiated public let service: any Service
			}
			"""]),
			ModuleFixture(name: "Mid", packageName: "Mid", swiftFileContentByFilePath: ["MidTypes.swift": """
			import Core
			import SafeDI

			@Instantiable(generateMock: .public)
			public final class Book: Instantiable {
			    init(pageBuilder: Instantiator<Page>) { self.pageBuilder = pageBuilder }
			    @Instantiated public let pageBuilder: Instantiator<Page>
			}
			"""], dependencies: ["Core"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: ["AppTypes.swift": """
			import Core
			import Mid
			import SafeDI

			@Instantiable
			public final class Token: Instantiable {
			    public init() {}
			}

			@Instantiable(fulfillingAdditionalTypes: [(any Service).self])
			public final class DefaultService: Service, Instantiable {
			    public init(token: LazilyInstantiated<Token>, book: Book) { self.token = token; self.book = book }
			    @Received public let token: LazilyInstantiated<Token>
			    @Instantiated public let book: Book
			}

			\(caller.attribute)
			public final class Screen: Instantiable {
			    public init(token: LazilyInstantiated<Token>, page: Page) { self.token = token; self.page = page }
			    @Instantiated public let token: LazilyInstantiated<Token>
			    @Instantiated public let page: Page
			}
			"""], dependencies: ["Core", "Mid"]),
		]
	}

	/// Two called types, `G`, which `Root` builds, and `F`, which `LiveG` builds in a fill of `G`’s place `gapi`: `F`’s place
	/// `api` is filled by `Live`, which reads `Root`’s `LazilyInstantiated<Log>`, and `F` is re-entered only through `G`’s
	/// fill: `Live` itself builds `G` again, or, where `layout` says so, `F` also holds `b: B`, whose place `other`
	/// `LiveOther` fills, building `G` again. `G` and `F` each build `Z`, which receives `log`, so each mock binds it by value.
	/// Where `layout` says so, `F` holds `api` on its root level, or a third called type, `H`, is between them: `LiveG`
	/// builds `H`, whose place `hapi` `LiveH` fills, building `F`.
	private static func reenteredThroughAnotherCallsFillModules(caller: CallingMockCallerKind, layout: ReenteredThroughAnotherCallsFillLayout) -> [ModuleFixture] {
		var appFiles = [
			"AppTypes.swift": "import Feat\nimport SafeDI\n\n" + reenteredThroughAnotherCallsFillAppTypes(rootAttribute: caller.attribute(listed: "@Instantiable(isRoot: true)"), layout: layout),
		]
		if caller == .listed {
			appFiles["SafeDIConfiguration.swift"] = "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Root\"])\n"
		}
		return [
			ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContentByFilePath: ["FeatTypes.swift": reenteredThroughAnotherCallsFillFeatureTypes(callee: twinCalledTypes, layout: layout)]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: appFiles, dependencies: ["Feat"]),
		]
	}

	/// `F`, a seam and public mock in module `Feat`, holds its place `api` on its root level, and `Z`, which receives `log`,
	/// so `F`’s mock binds `log` by value; `G`, another, holds its place `gapi` in `GA`, and `Z`. `Live` fills `api`, reads
	/// `Root`’s `LazilyInstantiated<Log>` and builds `Instantiator<G>`; `LiveG` fills `gapi`, building `F` again where
	/// `secondCallBuildsFirstAgain`. `Root`, the calling mock `caller` says, builds `log` and `f: F`.
	private static func secondCallFromCalledTypesRootModules(caller: CallingMockCallerKind, secondCallBuildsFirstAgain: Bool) -> [ModuleFixture] {
		var appFiles = [
			"AppTypes.swift": "import Feat\nimport SafeDI\n\n" + secondCallFromCalledTypesRootAppTypes(rootAttribute: caller.attribute(listed: "@Instantiable(isRoot: true)"), secondCallBuildsFirstAgain: secondCallBuildsFirstAgain),
		]
		if caller == .listed {
			appFiles["SafeDIConfiguration.swift"] = "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Root\"])\n"
		}
		return [
			ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContentByFilePath: ["FeatTypes.swift": secondCallFromCalledTypesRootFeatureTypes(callee: twinCalledTypes)]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: appFiles, dependencies: ["Feat"]),
		]
	}

	/// `secondCallFromCalledTypesRootModules`’ types in one module, `Root` a root: what inline builds.
	private static func secondCallFromCalledTypesRootInlineModules(secondCallBuildsFirstAgain: Bool) -> [ModuleFixture] {
		var types = secondCallFromCalledTypesRootFeatureTypes(callee: "@Instantiable")
		types += "\n\n"
		types += secondCallFromCalledTypesRootAppTypes(rootAttribute: "@Instantiable(isRoot: true)", secondCallBuildsFirstAgain: secondCallBuildsFirstAgain)
		return [ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: ["AppTypes.swift": types])]
	}

	/// `F` and `G`, declared with `callee`, and the types their trees build, of `secondCallFromCalledTypesRootModules`.
	private static func secondCallFromCalledTypesRootFeatureTypes(callee: String) -> String {
		"""
		import SafeDI

		public protocol Api {}

		public protocol GApi {}

		@Instantiable
		public final class Log: Instantiable {
		    public init() {}
		}

		@Instantiable
		public final class Z: Instantiable {
		    init(log: Log) {
		        self.log = log
		    }

		    @Received public let log: Log
		}

		@Instantiable
		public final class GA: Instantiable {
		    init(gapi: any GApi) {
		        self.gapi = gapi
		    }

		    @Instantiated public let gapi: any GApi
		}

		\(callee)
		public final class F: Instantiable {
		    public init(api: any Api, z: Z) {
		        self.api = api
		        self.z = z
		    }

		    @Instantiated public let api: any Api
		    @Instantiated public let z: Z
		}

		\(callee)
		public final class G: Instantiable {
		    public init(ga: GA, z: Z) {
		        self.ga = ga
		        self.z = z
		    }

		    @Instantiated public let ga: GA
		    @Instantiated public let z: Z
		}
		"""
	}

	/// `Live`, `LiveG` and `Root`, declared with `rootAttribute`, of `secondCallFromCalledTypesRootModules`.
	private static func secondCallFromCalledTypesRootAppTypes(rootAttribute: String, secondCallBuildsFirstAgain: Bool) -> String {
		let liveG = secondCallBuildsFirstAgain
			? """
			@Instantiable(fulfillingAdditionalTypes: [GApi.self])
			public final class LiveG: GApi, Instantiable {
			    public init(f: F) {
			        self.f = f
			    }

			    @Instantiated public let f: F
			}
			"""
			: """
			@Instantiable(fulfillingAdditionalTypes: [GApi.self])
			public final class LiveG: GApi, Instantiable {
			    public init() {}
			}
			"""
		return """
		@Instantiable(fulfillingAdditionalTypes: [Api.self])
		public final class Live: Api, Instantiable {
		    public init(log: LazilyInstantiated<Log>, gBuilder: Instantiator<G>) {
		        self.log = log
		        self.gBuilder = gBuilder
		    }

		    @Received public let log: LazilyInstantiated<Log>
		    @Instantiated public let gBuilder: Instantiator<G>
		}

		\(liveG)

		\(rootAttribute)
		public final class Root: Instantiable {
		    public init(log: LazilyInstantiated<Log>, f: F) {
		        self.log = log
		        self.f = f
		    }

		    @Instantiated public let log: LazilyInstantiated<Log>
		    @Instantiated public let f: F
		}
		"""
	}

	/// What `Root`’s mock and inline `Root` build; whether `Live` holds `Root`’s wrapper, and `F`’s `Z` and the `Z` of the
	/// `G` `Live` builds its value.
	private static let secondCallFromCalledTypesRootProbes = {
		func probe(_ name: String, _ expression: (String) -> String) -> DifferentialValueProbe {
			DifferentialValueProbe(name: name, expression: expression("Root.mock()"), knownRightExpression: expression("Root()"))
		}
		return [
			probe("Root") { $0 },
			probe("Live’s log is Root’s") { "{ let root = \($0); return (root.f.api as! Live).log === root.log }()" },
			probe("F’s Z holds Root’s Log") { "{ let root = \($0); return root.f.z.log === root.log.instance }()" },
			probe("the Z of the G Live builds holds Root’s Log") { "{ let root = \($0); return (root.f.api as! Live).gBuilder.instantiate().z.log === root.log.instance }()" },
		]
	}()

	/// `reenteredThroughAnotherCallsFillModules`’ types in one module, `Root` a root: what inline builds.
	private static func reenteredThroughAnotherCallsFillInlineModules(layout: ReenteredThroughAnotherCallsFillLayout) -> [ModuleFixture] {
		var types = reenteredThroughAnotherCallsFillFeatureTypes(callee: "@Instantiable", layout: layout)
		types += "\n\n"
		types += reenteredThroughAnotherCallsFillAppTypes(rootAttribute: "@Instantiable(isRoot: true)", layout: layout)
		return [ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: ["AppTypes.swift": types])]
	}

	/// `F` and `G`, declared with `callee`, and the types their trees build, of `reenteredThroughAnotherCallsFillModules`.
	private static func reenteredThroughAnotherCallsFillFeatureTypes(callee: String, layout: ReenteredThroughAnotherCallsFillLayout) -> String {
		var fProperties = [layout.placeIsOnCalledTypesRootLevel ? (label: "api", type: "any Api") : (label: "a", type: "A"), (label: "z", type: "Z")]
		var other = ""
		if layout.otherPlacesFillBuildsOuterCallAgain {
			fProperties.insert((label: "b", type: "B"), at: 1)
			other = """
			public protocol Other {}

			@Instantiable
			public final class B: Instantiable {
			    init(other: any Other) {
			        self.other = other
			    }

			    @Instantiated public let other: any Other
			}


			"""
		}
		let fParameters = fProperties.map { "\($0.label): \($0.type)" }.joined(separator: ", ")
		let fAssignments = fProperties.map { "        self.\($0.label) = \($0.label)" }.joined(separator: "\n")
		let fDeclarations = fProperties.map { "    @Instantiated public let \($0.label): \($0.type)" }.joined(separator: "\n")
		var third = ""
		if layout == .thirdCallsFillBuildsCalledTypeAgain {
			third = """


			public protocol HApi {}

			@Instantiable
			public final class HA: Instantiable {
			    init(hapi: any HApi) {
			        self.hapi = hapi
			    }

			    @Instantiated public let hapi: any HApi
			}

			\(callee)
			public final class H: Instantiable {
			    public init(ha: HA, z: Z) {
			        self.ha = ha
			        self.z = z
			    }

			    @Instantiated public let ha: HA
			    @Instantiated public let z: Z
			}
			"""
		}
		return """
		import SafeDI

		public protocol Api {}

		public protocol GApi {}

		@Instantiable
		public final class Log: Instantiable {
		    public init() {}
		}

		@Instantiable
		public final class A: Instantiable {
		    init(api: any Api) {
		        self.api = api
		    }

		    @Instantiated public let api: any Api
		}

		@Instantiable
		public final class Z: Instantiable {
		    init(log: Log) {
		        self.log = log
		    }

		    @Received public let log: Log
		}

		@Instantiable
		public final class GA: Instantiable {
		    init(gapi: any GApi) {
		        self.gapi = gapi
		    }

		    @Instantiated public let gapi: any GApi
		}

		\(other)\(callee)
		public final class F: Instantiable {
		    public init(\(fParameters)) {
		\(fAssignments)
		    }

		\(fDeclarations)
		}

		\(callee)
		public final class G: Instantiable {
		    public init(ga: GA, z: Z) {
		        self.ga = ga
		        self.z = z
		    }

		    @Instantiated public let ga: GA
		    @Instantiated public let z: Z
		}\(third)
		"""
	}

	/// `Live`, `LiveG`, `LiveOther` and `LiveH` where `layout` has them, and `Root`, declared with `rootAttribute`, of
	/// `reenteredThroughAnotherCallsFillModules`.
	private static func reenteredThroughAnotherCallsFillAppTypes(rootAttribute: String, layout: ReenteredThroughAnotherCallsFillLayout) -> String {
		var types = switch layout {
		case .fillBuildsOuterCallAgain, .thirdCallsFillBuildsCalledTypeAgain:
			"""
			@Instantiable(fulfillingAdditionalTypes: [Api.self])
			public final class Live: Api, Instantiable {
			    public init(log: LazilyInstantiated<Log>, gBuilder: Instantiator<G>) {
			        self.log = log
			        self.gBuilder = gBuilder
			    }

			    @Received public let log: LazilyInstantiated<Log>
			    @Instantiated public let gBuilder: Instantiator<G>
			}
			"""
		case .otherPlacesFillBuildsOuterCallAgain, .otherPlacesFillBuildsOuterCallAgainWithPlaceOnCalledTypesRootLevel:
			"""
			@Instantiable(fulfillingAdditionalTypes: [Api.self])
			public final class Live: Api, Instantiable {
			    public init(log: LazilyInstantiated<Log>) {
			        self.log = log
			    }

			    @Received public let log: LazilyInstantiated<Log>
			}

			@Instantiable(fulfillingAdditionalTypes: [Other.self])
			public final class LiveOther: Other, Instantiable {
			    public init(gBuilder: Instantiator<G>) {
			        self.gBuilder = gBuilder
			    }

			    @Instantiated public let gBuilder: Instantiator<G>
			}
			"""
		}
		if layout == .thirdCallsFillBuildsCalledTypeAgain {
			types += """


			@Instantiable(fulfillingAdditionalTypes: [GApi.self])
			public final class LiveG: GApi, Instantiable {
			    public init(h: H) {
			        self.h = h
			    }

			    @Instantiated public let h: H
			}

			@Instantiable(fulfillingAdditionalTypes: [HApi.self])
			public final class LiveH: HApi, Instantiable {
			    public init(f: F) {
			        self.f = f
			    }

			    @Instantiated public let f: F
			}
			"""
		} else {
			types += """


			@Instantiable(fulfillingAdditionalTypes: [GApi.self])
			public final class LiveG: GApi, Instantiable {
			    public init(f: F) {
			        self.f = f
			    }

			    @Instantiated public let f: F
			}
			"""
		}
		types += """


		\(rootAttribute)
		public final class Root: Instantiable {
		    public init(log: LazilyInstantiated<Log>, g: G) {
		        self.log = log
		        self.g = g
		    }

		    @Instantiated public let log: LazilyInstantiated<Log>
		    @Instantiated public let g: G
		}
		"""
		return types
	}

	/// What `Root`’s mock and inline `Root` build; whether the `Live` of `G`’s fill’s `F` holds `Root`’s wrapper; and whether
	/// the `Live` of the `F` in `G` built again, and that `G`’s and `F`’s `Z`, hold `Root`’s wrapper and its value.
	private static func reenteredThroughAnotherCallsFillProbes(layout: ReenteredThroughAnotherCallsFillLayout) -> [DifferentialValueProbe] {
		func calledTypeF(in g: String) -> String {
			switch layout {
			case .fillBuildsOuterCallAgain, .otherPlacesFillBuildsOuterCallAgain, .otherPlacesFillBuildsOuterCallAgainWithPlaceOnCalledTypesRootLevel:
				"(\(g).ga.gapi as! LiveG).f"
			case .thirdCallsFillBuildsCalledTypeAgain:
				"((\(g).ga.gapi as! LiveG).h.ha.hapi as! LiveH).f"
			}
		}
		func live(in f: String) -> String {
			layout.placeIsOnCalledTypesRootLevel ? "(\(f).api as! Live)" : "(\(f).a.api as! Live)"
		}
		let f = calledTypeF(in: "root.g")
		let gAgain = layout.otherPlacesFillBuildsOuterCallAgain
			? "(\(f).b.other as! LiveOther).gBuilder.instantiate()"
			: "\(live(in: f)).gBuilder.instantiate()"
		let fAgain = calledTypeF(in: gAgain)
		func probe(_ name: String, _ expression: (String) -> String) -> DifferentialValueProbe {
			DifferentialValueProbe(name: name, expression: expression("Root.mock()"), knownRightExpression: expression("Root()"))
		}
		return [
			probe("Root") { $0 },
			probe("Live’s log is Root’s") { "{ let root = \($0); return \(live(in: f)).log === root.log }()" },
			probe("the Live of F in G built again holds Root’s log") { "{ let root = \($0); return \(live(in: fAgain)).log === root.log }()" },
			probe("the Z of G built again holds Root’s Log") { "{ let root = \($0); return \(gAgain).z.log === root.log.instance }()" },
			probe("the Z of F in G built again holds Root’s Log") { "{ let root = \($0); return \(fAgain).z.log === root.log.instance }()" },
		]
	}

	/// The adopter’s shape with two places of `api`, where `F`’s mock binds `log` by value, `Z` receiving it: `A`’s, on `F`’s
	/// level, which `F`’s copy reaches, and `A`’s beneath a level that instantiates a `log` of its own, `B`, or, where
	/// `variation` says so, `B2`, built in `F`’s `SendableInstantiator`. `Live` fills both, reading the caller’s `log` in a
	/// lazy wrapper at the first place and the level’s at the second. Where `variation` says so, `F` builds no `Z`, so it
	/// holds no copy of `log`, or `B` holds its place in `A2`, as an `ErasedInstantiator`.
	private static func placesDisagreeModules(caller: CallingMockCallerKind, variation: PlacesDisagreeVariation) -> [ModuleFixture] {
		let wrapper = variation.wrapper.name
		let sendable = variation.levelIsBuiltInSendableFunction ? ", Sendable" : ""
		let zLog = variation == .levelInSendableFunctionBesidePlaceReceivedOnlyIfAvailable ? "Log?" : "Log"
		let zReceive = variation == .levelInSendableFunctionBesidePlaceReceivedOnlyIfAvailable ? "@Received(onlyIfAvailable: true)" : "@Received"
		let level = variation.levelIsBuiltInSendableFunction ? (label: "b2Builder", type: "SendableInstantiator<B2>", name: "B2") : (label: "b", type: "B", name: "B")
		var fProperties = [(label: "a", type: "A"), (label: level.label, type: level.type)]
		if variation != .levelBesidePlaceWithoutCopy {
			fProperties.append((label: "z", type: "Z"))
		}
		let fParameters = fProperties.map { "\($0.label): \($0.type)" }.joined(separator: ", ")
		let fAssignments = fProperties.map { "        self.\($0.label) = \($0.label)" }.joined(separator: "\n")
		let fDeclarations = fProperties.map { "    @Instantiated public let \($0.label): \($0.type)" }.joined(separator: "\n")
		var levelPlace = (label: "a", type: "A")
		var erasedPlace = ""
		if variation == .levelBesideErasedPlace {
			levelPlace = (label: "a", type: "A2")
			erasedPlace = """


			@Instantiable
			public final class A2: Instantiable {
			    init(api: ErasedInstantiator<(), any Api>) {
			        self.api = api
			    }

			    @Instantiated(fulfilledByType: "Api") public let api: ErasedInstantiator<(), any Api>
			}
			"""
		}
		var appFiles = ["AppTypes.swift": """
		import Feat
		import SafeDI

		@Instantiable(fulfillingAdditionalTypes: [Api.self])
		public final class Live: Api, Instantiable\(sendable) {
		    public init(log: \(wrapper)<Log>) {
		        self.log = log
		    }

		    @Received public let log: \(wrapper)<Log>
		}

		\(caller.attribute(listed: "@Instantiable(isRoot: true)"))
		public final class Root: Instantiable {
		    public init(log: \(wrapper)<Log>, f: F) {
		        self.log = log
		        self.f = f
		    }

		    @Instantiated public let log: \(wrapper)<Log>
		    @Instantiated public let f: F
		}
		"""]
		if caller == .listed {
			appFiles["SafeDIConfiguration.swift"] = "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Root\"])\n"
		}
		return [
			ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContentByFilePath: ["FeatTypes.swift": """
			import SafeDI

			public protocol Api\(sendable.isEmpty ? "" : ": Sendable") {}

			@Instantiable
			public final class Log: Instantiable, Sendable {
			    public init() {}
			}

			@Instantiable
			public final class A: Instantiable\(sendable) {
			    init(api: any Api) {
			        self.api = api
			    }

			    @Instantiated public let api: any Api
			}

			@Instantiable
			public final class Z: Instantiable\(sendable) {
			    init(log: \(zLog)) {
			        self.log = log
			    }

			    \(zReceive) public let log: \(zLog)
			}

			@Instantiable
			public final class \(level.name): Instantiable\(sendable) {
			    init(log: \(wrapper)<Log>, \(levelPlace.label): \(levelPlace.type)) {
			        self.log = log
			        self.\(levelPlace.label) = \(levelPlace.label)
			    }

			    @Instantiated public let log: \(wrapper)<Log>
			    @Instantiated public let \(levelPlace.label): \(levelPlace.type)
			}\(erasedPlace)

			\(twinCalledTypes)
			public final class F: Instantiable\(sendable) {
			    public init(\(fParameters)) {
			\(fAssignments)
			    }

			\(fDeclarations)
			}
			"""]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: appFiles, dependencies: ["Feat"]),
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

	/// `Root` builds `aBuilder` and `SignedIn`, whose `router` place `LiveRouter` fills, receiving `aBuilder`, only if available
	/// where `receivesOnlyIfAvailable`; `AScreen`, which `aBuilder` builds, receives `signedIn`. Where `listsCaller`, module
	/// `App` lists `Root` in `additionalMocksToGenerate`.
	private static func callerDeclaredBuilderCycleModules(caller: String, callee: String, receivesOnlyIfAvailable: Bool = false, listsCaller: Bool = false) -> [ModuleFixture] {
		let receive = receivesOnlyIfAvailable ? "@Received(onlyIfAvailable: true)" : "@Received"
		let receivedType = receivesOnlyIfAvailable ? "Instantiator<AScreen>?" : "Instantiator<AScreen>"
		var appFiles = [
			"AppTypes.swift": """
			import SafeDI
			import Feature

			@Instantiable(fulfillingAdditionalTypes: [Router.self])
			final class LiveRouter: Router, Instantiable {
			    init(aBuilder: \(receivedType)) {
			        self.aBuilder = aBuilder
			    }

			    \(receive) private let aBuilder: \(receivedType)
			}

			\(caller)
			public final class Root: Instantiable {
			    public init(aBuilder: Instantiator<AScreen>, signedIn: SignedIn) {
			        self.aBuilder = aBuilder
			        self.signedIn = signedIn
			    }

			    @Instantiated private let aBuilder: Instantiator<AScreen>
			    @Instantiated private let signedIn: SignedIn
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

				public protocol Router {}

				@Instantiable
				public final class AScreen: Instantiable {
				    public init(signedIn: SignedIn) {
				        self.signedIn = signedIn
				    }

				    @Received private let signedIn: SignedIn
				}

				\(callee)
				public final class SignedIn: Instantiable {
				    public init(router: any Router) {
				        self.router = router
				    }

				    @Instantiated private let router: any Router
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: appFiles, dependencies: ["Feature"]),
		]
	}

	/// The cycle `callerDeclaredBuilderCycleModules` closes, which the calling mock and its twin report alike.
	private static func callerDeclaredBuilderCycleDiagnostics(_ fixtures: [String: FixturePaths]) -> String {
		"""
		\(fixtures["App"]!["AppTypes.swift"]):10:5: error: Dependency cycle: @Instantiated `aBuilder: Instantiator<AScreen>` -> @Received `signedIn: SignedIn` -> @Received `aBuilder: Instantiator<AScreen>`. `aBuilder: Instantiator<AScreen>` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
		"""
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

	/// W4 with its first remedy applied: `SignedIn` instantiates `pair`, which `App`’s `LivePair` fills, and whose tree builds
	/// `feedBuilder` and `settingsBuilder` in their place. `Feed`, which `LivePair` builds, is `public`.
	private static func w4RestructuredModules(caller: String, callee: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContentByFilePath: [
				"FeatureTypes.swift": """
				import SafeDI

				public protocol FeedPage {}

				public protocol SettingsPage {}

				public protocol Pair {}

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
				    init(user: User, pair: any Pair) {
				        self.user = user
				        self.pair = pair
				    }

				    @Forwarded private let user: User
				    @Instantiated private let pair: any Pair
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

				@Instantiable(fulfillingAdditionalTypes: [Pair.self])
				final class LivePair: Pair, Instantiable {
				    init(feedBuilder: ErasedInstantiator<(), any FeedPage>, settingsBuilder: ErasedInstantiator<(), any SettingsPage>) {
				        self.feedBuilder = feedBuilder
				        self.settingsBuilder = settingsBuilder
				    }

				    @Instantiated(fulfilledByType: "Feed") private let feedBuilder: ErasedInstantiator<(), any FeedPage>
				    @Instantiated(fulfilledByType: "AppSettings") private let settingsBuilder: ErasedInstantiator<(), any SettingsPage>
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

	/// The plain W4 cycle with `feedBuilder` received only if available by `AppSettings`, which leads to W4’s error.
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

	/// The plain W4 cycle received only if available, then W4’s first remedy as worded: `SignedIn` instantiates `pair`,
	/// which `App`’s `LivePair` fills, and whose tree builds `feedBuilder` and `settings` in their place. `Feed`, which
	/// `LivePair` builds, is `public` with its initializer where `feedIsPublic`, as its access errors’ fix-its make it.
	private static func w4ConstantCycleOptionalRestructuredModules(caller: String, callee: String, feedIsPublic: Bool, appActiveCompilationConditions: [String] = []) -> [ModuleFixture] {
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
				\(feedIsPublic ? "public " : "")final class Feed: FeedPage, Instantiable {
				    \(feedIsPublic ? "public " : "")init(user: User, settings: any SettingsPage) {
				        self.user = user
				        self.settings = settings
				    }

				    @Received private let user: User
				    @Received private let settings: any SettingsPage
				}

				public protocol Pair {}

				\(callee)
				public final class SignedIn: Instantiable {
				    init(user: User, pair: any Pair) {
				        self.user = user
				        self.pair = pair
				    }

				    @Forwarded private let user: User
				    @Instantiated private let pair: any Pair
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

				@Instantiable(fulfillingAdditionalTypes: [Pair.self])
				final class LivePair: Pair, Instantiable {
				    init(feedBuilder: ErasedInstantiator<(), any FeedPage>, settings: any SettingsPage) {
				        self.feedBuilder = feedBuilder
				        self.settings = settings
				    }

				    @Instantiated(fulfilledByType: "Feed") private let feedBuilder: ErasedInstantiator<(), any FeedPage>
				    @Instantiated private let settings: any SettingsPage
				}

				\(caller)
				public final class Root: Instantiable {
				    public init(signedInBuilder: Instantiator<SignedIn>) {
				        self.signedInBuilder = signedInBuilder
				    }

				    @Instantiated private let signedInBuilder: Instantiator<SignedIn>
				}
				""",
			], dependencies: ["Feature"], activeCompilationConditions: appActiveCompilationConditions),
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

/// The builds of a calling mock’s module that do not tell the tool `DEBUG`, the mock condition: a release build, which
/// compiles no generated mock, and a debug build whose integration does not report `DEBUG`, as SwiftPM’s native backend
/// does not, which compiles the generated mock.
enum MockConditionInactiveBuild: CaseIterable, CustomTestStringConvertible {
	case release
	case debugWithoutMockCondition

	var testDescription: String {
		switch self {
		case .release:
			"release build"
		case .debugWithoutMockCondition:
			"debug build that does not report DEBUG"
		}
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

	/// What a build of `App` that does not tell the tool the mock condition generates, a release build or a debug build
	/// whose integration does not report `DEBUG`, alike: the place passed up, which an internal mock and a listed type’s
	/// take as the same parameter.
	var expectedFilesWhereMockConditionIsInactive: [String: String] {
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
			                self.init(panel: { _ in .init(__safeDI_noScope: __safeDI_builder) })
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

/// How a fill that builds a called type holding no copy of the caller’s `log` again reads `log`, which the re-entered
/// call’s root level function takes, as `Live`, which fills a place below the called type’s root, reads it: by value, or
/// only if available; how it builds the called type again, itself, through a child of its tree, or through another called
/// type whose fill builds it; and the wrapper the caller holds `log` in, if any.
struct ReenteredFunctionReadShape: CustomTestStringConvertible, Sendable {
	init(reentry: Reentry, fillReadsLogOnlyIfAvailable: Bool, rootWrapper: CallerLazyWrapper?, liveReadsLogOnlyIfAvailable: Bool = false) {
		self.reentry = reentry
		self.fillReadsLogOnlyIfAvailable = fillReadsLogOnlyIfAvailable
		self.rootWrapper = rootWrapper
		self.liveReadsLogOnlyIfAvailable = liveReadsLogOnlyIfAvailable
	}

	/// Each shape whose fill takes `log` only because the re-entered function takes it, so that it hands the function
	/// the value it takes (`Scope.labelsHandedToReenteredFunctions(by:)`). Where the caller holds `log` by value and the
	/// fill reads none, a fill that does not take it captures the caller’s value, which is what the function takes, so
	/// those shapes do not depend on it. Where the fill reads no `log` and the caller holds it lazily, the calling mock
	/// passes both places up (`DependencyTreeGenerator.holeTypesTheFillGatesPassUp(of:in:lazilyHeldValues:)`), so no fill
	/// takes it.
	static let all: [Self] = {
		var shapes = [Self]()
		let rootWrappers: [CallerLazyWrapper?] = [nil, .lazilyInstantiated, .sendableLazilyInstantiated]
		for reentry in [Reentry.direct, .throughOtherCall] {
			for rootWrapper in rootWrappers {
				shapes.append(Self(reentry: reentry, fillReadsLogOnlyIfAvailable: true, rootWrapper: rootWrapper))
			}
		}
		return shapes
	}()

	/// Each shape whose fill reads no `log` while the caller holds it lazily, which the calling mock passes up: for each
	/// way of building the called type again, `Live` reading `log` by value or only if available, and each wrapper.
	static let passedUp: [Self] = {
		var shapes = [Self]()
		for reentry in [Reentry.direct, .throughChild, .throughOtherCall] {
			for liveReadsLogOnlyIfAvailable in [false, true] {
				for rootWrapper in CallerLazyWrapper.allCases {
					shapes.append(Self(reentry: reentry, fillReadsLogOnlyIfAvailable: false, rootWrapper: rootWrapper, liveReadsLogOnlyIfAvailable: liveReadsLogOnlyIfAvailable))
				}
			}
		}
		return shapes
	}()

	enum Reentry: Sendable {
		case direct
		case throughChild
		case throughOtherCall
	}

	let reentry: Reentry
	let fillReadsLogOnlyIfAvailable: Bool
	let rootWrapper: CallerLazyWrapper?
	/// Whether `Live` receives `log` only if available, as `Log?`, rather than by value.
	let liveReadsLogOnlyIfAvailable: Bool

	/// The type of the caller’s `log`.
	var rootLog: String {
		rootWrapper.map { "\($0.name)<Log>" } ?? "Log"
	}

	var testDescription: String {
		var description = switch reentry {
		case .direct:
			"built again by the fill"
		case .throughChild:
			"built again through a child of the fill"
		case .throughOtherCall:
			"built again through another call’s fill"
		}
		description += fillReadsLogOnlyIfAvailable ? ", read only if available" : ", not read"
		description += liveReadsLogOnlyIfAvailable ? ", Live reads it only if available" : ""
		description += ", caller holds \(rootLog)"
		return description
	}
}

/// A called type that holds a copy of the caller’s `log` through its child `Z`, by value or only if available, one of whose
/// fills, `Live2`, instantiates a `log` of its own and builds the called type again, as `reentry` says, while another,
/// `Live`, fills a place below the called type’s root and reads `log`: each `Live` must hold the `log` nearest it, `Live2`’s
/// in the called type built again. `rootWrapper` says how `Root` holds its `log`, and `neighbour` adds one more variation.
struct RedeclaredValueShape: CustomTestStringConvertible, Sendable {
	init(reentry: ReenteredFunctionReadShape.Reentry, copyIsOptional: Bool, rootWrapper: CallerLazyWrapper?, neighbour: Neighbour = .none) {
		self.reentry = reentry
		self.copyIsOptional = copyIsOptional
		self.rootWrapper = rootWrapper
		self.neighbour = neighbour
	}

	/// Each way of building the called type again, each copy, and each way `Root` holds `log`.
	static let all: [Self] = {
		var shapes = [Self]()
		for reentry in [ReenteredFunctionReadShape.Reentry.direct, .throughChild, .throughOtherCall] {
			for copyIsOptional in [false, true] {
				for rootWrapper in [nil, CallerLazyWrapper.lazilyInstantiated, .sendableLazilyInstantiated] {
					shapes.append(Self(reentry: reentry, copyIsOptional: copyIsOptional, rootWrapper: rootWrapper))
				}
			}
		}
		return shapes
	}()

	/// The primary shape, built again by the fill, with a copy by value and `Root` holding `log` by value, with each
	/// neighbour.
	static let neighbours = [Neighbour.secondLabel, .placeTwoLevelsBelowRoot, .thirdRound, .midDeclaresValueAgain, .liveReadsCopyOnlyIfAvailable].map {
		Self(reentry: .direct, copyIsOptional: false, rootWrapper: nil, neighbour: $0)
	}

	/// One more variation of the primary shape.
	enum Neighbour: Sendable {
		case none
		/// `Root` also holds `session`, which `Z` and `Live` receive, and which no fill declares again.
		case secondLabel
		/// The place is beneath `A2`, beneath `A`, two levels below the called type’s root.
		case placeTwoLevelsBelowRoot
		/// The probes also build the called type a third time, from the `Live2` of the one built again.
		case thirdRound
		/// `Mid`, between `Root` and the called type, instantiates a `log` of its own.
		case midDeclaresValueAgain
		/// `Live` receives `log` only if available, where the copy is by value.
		case liveReadsCopyOnlyIfAvailable
	}

	let reentry: ReenteredFunctionReadShape.Reentry
	/// Whether `Z` receives `log` only if available, as `Log?`, as `Live` then does too.
	let copyIsOptional: Bool
	let rootWrapper: CallerLazyWrapper?
	let neighbour: Neighbour

	/// Whether `Live` receives `log` only if available, as `Log?`.
	var liveReadsLogOnlyIfAvailable: Bool {
		copyIsOptional || neighbour == .liveReadsCopyOnlyIfAvailable
	}

	/// The type of `Root`’s `log`.
	var rootLog: String {
		rootWrapper.map { "\($0.name)<Log>" } ?? "Log"
	}

	var testDescription: String {
		var description = switch reentry {
		case .direct:
			"built again by the fill"
		case .throughChild:
			"built again through a child of the fill"
		case .throughOtherCall:
			"built again through another call’s fill"
		}
		description += copyIsOptional ? ", copy only if available" : ", copy by value"
		description += ", Root holds \(rootLog)"
		switch neighbour {
		case .none:
			break
		case .secondLabel:
			description += ", a second label"
		case .placeTwoLevelsBelowRoot:
			description += ", place two levels below the root"
		case .thirdRound:
			description += ", built a third time"
		case .midDeclaresValueAgain:
			description += ", Mid declares log again"
		case .liveReadsCopyOnlyIfAvailable:
			description += ", Live reads the copy only if available"
		}
		return description
	}
}

/// Where a called public mock’s place is in its tree, and what declares the value its fill reads on the way: a level
/// below the root, beneath `A`, the root level itself, or a level beneath `A` whose `B`, between the root and `A`,
/// instantiates the value again in `wrapper`’s form.
enum LazyValueLayout: CustomTestStringConvertible, Sendable {
	case belowRoot
	case atRoot
	case redeclaredBelowRoot(CallerLazyWrapper)

	var testDescription: String {
		switch self {
		case .belowRoot:
			"place below the root"
		case .atRoot:
			"place on the root level"
		case let .redeclaredBelowRoot(wrapper):
			"place below a level that declares a \(wrapper.name) again"
		}
	}
}

/// The lazy wrapper a calling mock’s caller holds a value in, and the instantiator a fill of the called public mock builds
/// the called type again in: a `LazilyInstantiated` in an `Instantiator`, or a `SendableLazilyInstantiated` in either
/// instantiator. A `LazilyInstantiated` read inside a `SendableInstantiator`’s `@Sendable` function is an error.
enum ReenteringWrapperPair: CaseIterable, CustomTestStringConvertible, Sendable {
	case lazilyInstantiatedInInstantiator
	case sendableLazilyInstantiatedInInstantiator
	case sendableLazilyInstantiatedInSendableInstantiator

	var wrapper: CallerLazyWrapper {
		switch self {
		case .lazilyInstantiatedInInstantiator:
			.lazilyInstantiated
		case .sendableLazilyInstantiatedInInstantiator, .sendableLazilyInstantiatedInSendableInstantiator:
			.sendableLazilyInstantiated
		}
	}

	var instantiator: String {
		switch self {
		case .lazilyInstantiatedInInstantiator, .sendableLazilyInstantiatedInInstantiator:
			"Instantiator"
		case .sendableLazilyInstantiatedInSendableInstantiator:
			"SendableInstantiator"
		}
	}

	var testDescription: String {
		"\(wrapper.name) in \(instantiator)"
	}
}

/// Where a called public mock’s second place, `other`, whose fill builds the called type again, is, and what builds it
/// again: on `B`’s level, beside `A`’s, where `api` is, its fill building it; on `A`’s level, beside `api`; or on `B`’s
/// level, its fill’s child building it.
enum ReenteringOtherPlaceLayout: CaseIterable, CustomTestStringConvertible, Sendable {
	case otherLevel
	case placesLevel
	case childOfOtherFill

	var testDescription: String {
		switch self {
		case .otherLevel:
			"other place on another level"
		case .placesLevel:
			"other place beside the place"
		case .childOfOtherFill:
			"other fill’s child builds F again"
		}
	}
}

/// What changes in the shape whose place on the called type’s root level reads the caller’s lazy value while a second place
/// below it builds the called type again (`rootLevelReaderModules`): nothing; a mocked `Mid` between `Root` and `F`; the
/// second place a level further down; the place an `ErasedInstantiator<(), any Api>`; `Z` receiving `log` only if
/// available; or `B`, which holds the second place, instantiating a `log` of its own above it.
enum RootLevelReaderVariation: CustomTestStringConvertible, Sendable {
	case plain
	case mockedTypeBetween
	case otherPlaceTwoLevelsDown
	case erasedPlace
	case receivedOnlyIfAvailable
	case levelDeclaresValueAgainAboveOtherPlace

	var testDescription: String {
		switch self {
		case .plain:
			"as drawn"
		case .mockedTypeBetween:
			"mocked type between"
		case .otherPlaceTwoLevelsDown:
			"other place two levels down"
		case .erasedPlace:
			"erased place"
		case .receivedOnlyIfAvailable:
			"received only if available"
		case .levelDeclaresValueAgainAboveOtherPlace:
			"level declares log again above other place"
		}
	}
}

/// Where the level that instantiates a `log` of its own above the second place of `api` is (`placesDisagreeModules`): beside
/// `A`, holding the `LazilyInstantiated` the fill reads, with `F` holding a by-value copy of `log` or none, or with the
/// level holding its place as an `ErasedInstantiator`; or built in a `SendableInstantiator`, holding a
/// `SendableLazilyInstantiated`, with `Z` receiving `log` outright or only if available.
enum PlacesDisagreeVariation: CaseIterable, CustomTestStringConvertible, Sendable {
	case levelBesidePlace
	case levelBesidePlaceWithoutCopy
	case levelBesideErasedPlace
	case levelInSendableFunctionBesidePlace
	case levelInSendableFunctionBesidePlaceReceivedOnlyIfAvailable

	var wrapper: CallerLazyWrapper {
		levelIsBuiltInSendableFunction ? .sendableLazilyInstantiated : .lazilyInstantiated
	}

	/// Whether `F` builds the level in a `SendableInstantiator`.
	var levelIsBuiltInSendableFunction: Bool {
		switch self {
		case .levelBesidePlace, .levelBesidePlaceWithoutCopy, .levelBesideErasedPlace:
			false
		case .levelInSendableFunctionBesidePlace, .levelInSendableFunctionBesidePlaceReceivedOnlyIfAvailable:
			true
		}
	}

	var testDescription: String {
		switch self {
		case .levelBesidePlace:
			"level beside the place"
		case .levelBesidePlaceWithoutCopy:
			"level beside the place, F holding no copy"
		case .levelBesideErasedPlace:
			"level beside the place, the level’s place erased"
		case .levelInSendableFunctionBesidePlace:
			"level in a @Sendable function beside the place"
		case .levelInSendableFunctionBesidePlaceReceivedOnlyIfAvailable:
			"level in a @Sendable function beside the place, Z receiving only if available"
		}
	}
}

/// What builds the outer called type `G` again in `reenteredThroughAnotherCallsFillModules`: the fill of `F`’s place
/// that reads the caller’s lazy value, or the fill of `F`’s second place, `other`, with the place below `F`’s root or on
/// its root level; or the fill of `F`’s place where a third called type, `H`, is between `G` and `F`.
enum ReenteredThroughAnotherCallsFillLayout: CaseIterable, CustomTestStringConvertible, Sendable {
	case fillBuildsOuterCallAgain
	case otherPlacesFillBuildsOuterCallAgain
	case otherPlacesFillBuildsOuterCallAgainWithPlaceOnCalledTypesRootLevel
	case thirdCallsFillBuildsCalledTypeAgain

	/// Whether `F` holds `b: B`, whose place `other` `LiveOther` fills, building `G` again.
	var otherPlacesFillBuildsOuterCallAgain: Bool {
		switch self {
		case .fillBuildsOuterCallAgain, .thirdCallsFillBuildsCalledTypeAgain:
			false
		case .otherPlacesFillBuildsOuterCallAgain, .otherPlacesFillBuildsOuterCallAgainWithPlaceOnCalledTypesRootLevel:
			true
		}
	}

	/// Whether `F` holds the place `api` on its root level, rather than in `A`.
	var placeIsOnCalledTypesRootLevel: Bool {
		self == .otherPlacesFillBuildsOuterCallAgainWithPlaceOnCalledTypesRootLevel
	}

	var testDescription: String {
		switch self {
		case .fillBuildsOuterCallAgain:
			"the reading fill builds G again"
		case .otherPlacesFillBuildsOuterCallAgain:
			"another place’s fill builds G again"
		case .otherPlacesFillBuildsOuterCallAgainWithPlaceOnCalledTypesRootLevel:
			"another place’s fill builds G again, the place on F’s root level"
		case .thirdCallsFillBuildsCalledTypeAgain:
			"the reading fill builds G again, H between G and F"
		}
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

	/// `Live`, which fills the place and receives `received`, a label and its type, and instantiates each of `instantiated`.
	func fill(receiving received: String, instantiating instantiated: [String] = []) -> String {
		let label = String(received.prefix { $0 != ":" })
		var attribute = "@Instantiable(fulfillingAdditionalTypes: [Api.self])"
		var parameters = [String]()
		var assignments = [String]()
		var declarations = [String]()
		if self == .deferred {
			attribute = "@Instantiable"
			parameters.append("id: Int")
			assignments.append("self.id = id")
			declarations.append("@Forwarded public let id: Int")
		}
		parameters.append(received)
		assignments.append("self.\(label) = \(label)")
		declarations.append("@Received public let \(received)")
		for dependency in instantiated {
			let dependencyLabel = String(dependency.prefix { $0 != ":" })
			parameters.append(dependency)
			assignments.append("self.\(dependencyLabel) = \(dependencyLabel)")
			declarations.append("@Instantiated public let \(dependency)")
		}
		var lines = [attribute, "public final class Live: Api, Instantiable {", "    public init(\(parameters.joined(separator: ", "))) {"]
		lines += assignments.map { "        \($0)" }
		lines += ["    }", ""]
		lines += declarations.map { "    \($0)" }
		lines.append("}")
		return lines.joined(separator: "\n")
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

/// The kind of a calling mock: `generateMock: true`, `generateMock: .public`, or a type its module lists in
/// `additionalMocksToGenerate`, whose mock is internal.
enum CallingMockCallerKind: CaseIterable, CustomTestStringConvertible, Sendable {
	case `internal`
	case `public`
	case listed

	/// The caller’s attribute line, or `listedAttribute` where its module lists it.
	func attribute(listed listedAttribute: String) -> String {
		switch self {
		case .internal:
			CallingMockCaller.internal.attribute
		case .public:
			CallingMockCaller.public.attribute
		case .listed:
			listedAttribute
		}
	}

	/// The kind of the mock that calls: a listed type’s is internal.
	var callingMockCaller: CallingMockCaller {
		switch self {
		case .internal, .listed:
			.internal
		case .public:
			.public
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
}

/// Which type of `App` is the calling mock, where `Root` instantiates `log` and `Mid`, beneath it, builds `F`, and how
/// `Mid` holds `log`.
enum LazyValueChain: CustomTestStringConvertible, Sendable {
	/// `Mid.mock()`, where `Mid` declares nothing but `F`.
	case mockedMidBuildingCallBesideNothing
	/// `Mid.mock()`, where `Mid` receives `log`.
	case mockedMidReceivingValue
	/// `Root.mock()`, where `Mid` declares nothing but `F`.
	case unmockedMid
	/// `Root.mock()`, where `Root` instantiates `appLog` and `Mid` receives it as `log`.
	case unmockedMidReceivingValueUnderAlias

	/// Whether `Mid`’s mock is the calling mock, rather than `Root`’s.
	var mocksMid: Bool {
		switch self {
		case .mockedMidBuildingCallBesideNothing, .mockedMidReceivingValue:
			true
		case .unmockedMid, .unmockedMidReceivingValueUnderAlias:
			false
		}
	}

	var testDescription: String {
		switch self {
		case .mockedMidBuildingCallBesideNothing:
			"mocked Mid building F beside nothing"
		case .mockedMidReceivingValue:
			"mocked Mid receiving log"
		case .unmockedMid:
			"Mid without a mock"
		case .unmockedMidReceivingValueUnderAlias:
			"Mid without a mock receiving appLog as log"
		}
	}
}

/// How `Mid`’s mock binds the wrapper of `log` that the fill of `F`’s place reads apart from the label: beside the instance
/// `mock()` takes as `log` where nothing builds `Log`, for a place below `F`’s root, whose fill also has a child that reads
/// the instance, or a place on `F`’s root level; or, where `Log` is `@Instantiable`, a wrapper it promotes beside another
/// form of `log` it promotes, or beside a default-valued parameter of `mock()` labeled `log`.
enum MockRootBindingShape: CaseIterable, CustomTestStringConvertible, Sendable {
	case wrapperOfParameter
	case wrapperOfParameterAndItsInstance
	case wrapperOfParameterOnCalledTypesRootLevel
	case promotedBesideAnotherForm
	case promotedBesideDefaultValuedParameter

	/// The layout of `F`’s place.
	var layout: LazyValueLayout {
		placeIsOnCalledTypesRootLevel ? .atRoot : .belowRoot
	}

	var placeIsOnCalledTypesRootLevel: Bool {
		switch self {
		case .wrapperOfParameterOnCalledTypesRootLevel:
			true
		case .wrapperOfParameter, .wrapperOfParameterAndItsInstance, .promotedBesideAnotherForm, .promotedBesideDefaultValuedParameter:
			false
		}
	}

	/// Whether `Log` is `@Instantiable`, so `Mid`’s mock builds `log` rather than taking it.
	var logIsInstantiable: Bool {
		switch self {
		case .wrapperOfParameter, .wrapperOfParameterAndItsInstance, .wrapperOfParameterOnCalledTypesRootLevel:
			false
		case .promotedBesideAnotherForm, .promotedBesideDefaultValuedParameter:
			true
		}
	}

	/// Whether `Live` instantiates `child: LiveChild`, which receives `log` by value.
	var childReadsInstance: Bool {
		switch self {
		case .wrapperOfParameterAndItsInstance:
			true
		case .wrapperOfParameter, .wrapperOfParameterOnCalledTypesRootLevel, .promotedBesideAnotherForm, .promotedBesideDefaultValuedParameter:
			false
		}
	}

	/// The call of `Mid`’s mock, whose `caller` mock holds `log` in `wrapper`: a public mock takes the wrapper its tree
	/// receives (“A lazy value a public mock takes” in `public-mock-builders.md`), and an internal mock the instance.
	func mockCall(caller: CallingMockCaller, wrapper: CallerLazyWrapper) -> String {
		if logIsInstantiable {
			"Mid.mock()"
		} else if caller == .public {
			"Mid.mock(log: \(wrapper.name) { Log() })"
		} else {
			"Mid.mock(log: Log())"
		}
	}

	var testDescription: String {
		switch self {
		case .wrapperOfParameter:
			"wrapper of the parameter"
		case .wrapperOfParameterAndItsInstance:
			"wrapper of the parameter and its instance"
		case .wrapperOfParameterOnCalledTypesRootLevel:
			"wrapper of the parameter on F’s root level"
		case .promotedBesideAnotherForm:
			"promoted beside another form"
		case .promotedBesideDefaultValuedParameter:
			"promoted beside a default-valued parameter"
		}
	}
}

/// A wrapper a fill reads, and how `Mid`’s mock binds it apart from its label: each pair, for a test that also varies the
/// caller.
struct MockRootBindingForm: CustomTestStringConvertible, Sendable {
	static let all = CallerLazyWrapper.allCases.flatMap { wrapper in MockRootBindingShape.allCases.map { Self(wrapper: wrapper, shape: $0) } }

	let wrapper: CallerLazyWrapper
	let shape: MockRootBindingShape

	var testDescription: String {
		"\(wrapper.testDescription), \(shape.testDescription)"
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
