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

/// A fill of a hole an inner seam passes up through an outer seam that receives a value the outer seam builds where it
/// calls the inner seam: SafeDI rejects it, and the error's remedy must work, where the inner seam's module cannot see the
/// value's type too.
struct SafeDIToolSeamOuterSeamValueRemedyTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: The error

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingRemedyThatCompiles_whenInnerSeamsModuleCannotSeeReceivedType() async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LivePaymentService.swift"]):11:5: error: `LivePaymentService` receives `cart: Cart`, which `StoreScreen` builds where it calls `CheckoutScreen`, but `StoreScreen` passes the builder for `CheckoutScreen`’s `payments: PaymentService` (case `payments` of `paymentServiceBuilder`) on from its own caller, which cannot hand it `StoreScreen`’s values. Declare `@Received let cart: Cart` on `CheckoutScreen`, so the builder’s scope carries it (if module `Checkout` cannot see a type `cart: Cart` names, first declare that type in module `Checkout` or a module it depends on, with an initializer module `Store` can call), or declare an @Instantiable type that fulfills `PaymentService` in module `Store` or a module it lists among its SafeDI dependencies, so `StoreScreen` fills the builder itself.
			\(fixtures["Store"]!["StoreScreen.swift"]):12:5: note: `StoreScreen` declares `cart: Cart` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.shape(), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingSameRemedy_whenInnerSeamsModuleAlreadySeesReceivedType() async {
		// SafeDI cannot tell whether `Checkout` sees `Cart`, so the remedy is conditional here too.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LivePaymentService.swift"]):10:5: error: `LivePaymentService` receives `cart: Cart`, which `StoreScreen` builds where it calls `CheckoutScreen`, but `StoreScreen` passes the builder for `CheckoutScreen`’s `payments: PaymentService` (case `payments` of `paymentServiceBuilder`) on from its own caller, which cannot hand it `StoreScreen`’s values. Declare `@Received let cart: Cart` on `CheckoutScreen`, so the builder’s scope carries it (if module `Checkout` cannot see a type `cart: Cart` names, first declare that type in module `Checkout` or a module it depends on, with an initializer module `Store` can call), or declare an @Instantiable type that fulfills `PaymentService` in module `Store` or a module it lists among its SafeDI dependencies, so `StoreScreen` fills the builder itself.
			\(fixtures["Store"]!["StoreScreen.swift"]):12:5: note: `StoreScreen` declares `cart: Cart` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.shape(cartInCore: true), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingReceiveAlone_whenOuterAndInnerSeamsShareModule() async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LivePaymentService.swift"]):11:5: error: `LivePaymentService` receives `cart: Cart`, which `StoreScreen` builds where it calls `CheckoutScreen`, but `StoreScreen` passes the builder for `CheckoutScreen`’s `payments: PaymentService` (case `payments` of `paymentServiceBuilder`) on from its own caller, which cannot hand it `StoreScreen`’s values. Declare `@Received let cart: Cart` on `CheckoutScreen`, so the builder’s scope carries it, or declare an @Instantiable type that fulfills `PaymentService` in module `Store` or a module it lists among its SafeDI dependencies, so `StoreScreen` fills the builder itself.
			\(fixtures["Store"]!["StoreScreen.swift"]):11:5: note: `StoreScreen` declares `cart: Cart` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.shapeWithSeamsInOneModule(), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingTypeOnPath_whenTypeOnPathToCallDeclaresReceivedValue() async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LivePaymentService.swift"]):11:5: error: `LivePaymentService` receives `cart: Cart`, which `Aisle` builds on the path where `StoreScreen` calls `CheckoutScreen`, but `StoreScreen` passes the builder for `CheckoutScreen`’s `payments: PaymentService` (case `payments` of `paymentServiceBuilder`) on from its own caller, which cannot hand it that value. Declare `@Received let cart: Cart` on `CheckoutScreen`, so the builder’s scope carries it (if module `Checkout` cannot see a type `cart: Cart` names, first declare that type in module `Checkout` or a module it depends on, with an initializer module `Store` can call), or declare an @Instantiable type that fulfills `PaymentService` in module `Store` or a module it lists among its SafeDI dependencies, so `StoreScreen` fills the builder itself.
			\(fixtures["Store"]!["Aisle.swift"]):12:5: note: `Aisle` declares `cart: Cart` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.shape(onPath: true), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingTypesTheInstantiatorNames_whenFillReceivesInstantiatorOuterSeamBuilds() async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LivePaymentService.swift"]):11:5: error: `LivePaymentService` receives `cartBuilder: Instantiator<Cart>`, which `StoreScreen` builds where it calls `CheckoutScreen`, but `StoreScreen` passes the builder for `CheckoutScreen`’s `payments: PaymentService` (case `payments` of `paymentServiceBuilder`) on from its own caller, which cannot hand it `StoreScreen`’s values. Declare `@Received let cartBuilder: Instantiator<Cart>` on `CheckoutScreen`, so the builder’s scope carries it (if module `Checkout` cannot see a type `cartBuilder: Instantiator<Cart>` names, first declare that type in module `Checkout` or a module it depends on, with an initializer module `Store` can call), or declare an @Instantiable type that fulfills `PaymentService` in module `Store` or a module it lists among its SafeDI dependencies, so `StoreScreen` fills the builder itself.
			\(fixtures["Store"]!["StoreScreen.swift"]):12:5: note: `StoreScreen` declares `cartBuilder: Instantiator<Cart>` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.shape(asInstantiator: true), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	// MARK: The remedies, applied

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesEveryModule_whenReceivedTypeIsDeclaredWhereInnerSeamSeesItAndReceivedOnInnerSeam() async throws {
		try await expectEveryModuleCompiles(Self.shape(cartInCore: true, receivedOnInnerSeam: true))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesEveryModule_whenTypeOnPathPassesValueReceivedOnInnerSeam() async throws {
		try await expectEveryModuleCompiles(Self.shape(cartInCore: true, receivedOnInnerSeam: true, onPath: true))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesEveryModule_whenTypeAnInstantiatorNamesIsDeclaredWhereInnerSeamSeesItAndInstantiatorReceivedOnInnerSeam() async throws {
		try await expectEveryModuleCompiles(Self.shape(cartInCore: true, receivedOnInnerSeam: true, asInstantiator: true))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesEveryModule_whenOuterSeamsModuleFulfillsHole() async throws {
		try await expectEveryModuleCompiles(Self.shape(fulfilledInStore: true))
	}

	// MARK: Private

	private var filesToDelete: [URL]

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectEveryModuleCompiles(_ modules: [ModuleFixture], sourceLocation: SourceLocation = #_sourceLocation) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		#expect(compilation.modules.map(\.exitCode) == output.moduleNames.map { _ in 0 }, sourceLocation: sourceLocation)
		#expect(compilation.modules.flatMap(\.generatedCodeWarnings) == [], sourceLocation: sourceLocation)
	}

	/// `Cart`, as `Store` declares it, or as `Core` declares it, with an initializer `Store` can call.
	private static func cart(isPublic: Bool) -> String {
		"""
		import SafeDI

		@Instantiable
		public final class Cart: Instantiable {
		    \(isPublic ? "public " : "")init() {}
		}
		"""
	}

	/// The shape: `CheckoutScreen`, a seam in `Checkout`, has a hole `App` fills with `LivePaymentService`, which receives
	/// `cart`, a value `StoreScreen`, a seam in `Store`, builds where it calls `CheckoutScreen`.
	/// - Parameters:
	///   - cartInCore: Whether `Core` declares `Cart`, which `Checkout` then sees, in place of `Store`.
	///   - receivedOnInnerSeam: Whether `CheckoutScreen` receives `cart`.
	///   - onPath: Whether `Aisle`, which `StoreScreen` instantiates, declares `cart` and `checkout` in place of `StoreScreen`.
	///   - asInstantiator: Whether the value is `cartBuilder: Instantiator<Cart>`.
	///   - fulfilledInStore: Whether `Store`, in place of `App`, declares the type that fulfills `PaymentService`.
	private static func shape(
		cartInCore: Bool = false,
		receivedOnInnerSeam: Bool = false,
		onPath: Bool = false,
		asInstantiator: Bool = false,
		fulfilledInStore: Bool = false,
	) -> [ModuleFixture] {
		let cartProperty = asInstantiator ? "cartBuilder: Instantiator<Cart>" : "cart: Cart"
		let cartLabel = asInstantiator ? "cartBuilder" : "cart"
		let checkoutScreen = """
		import SafeDI
		import Core

		@Instantiable(generateDependencyTree: true)
		public final class CheckoutScreen: Instantiable {
		    init(\(receivedOnInnerSeam ? "\(cartProperty), " : "")payments: PaymentService) {
		\(receivedOnInnerSeam ? "        self.\(cartLabel) = \(cartLabel)\n" : "")        self.payments = payments
		    }

		\(receivedOnInnerSeam ? "    @Received private let \(cartProperty)\n" : "")    @Instantiated private let payments: PaymentService
		}
		"""
		let holder = onPath ? "Aisle" : "StoreScreen"
		let holderDeclaration = """
		import SafeDI
		import Core
		import Checkout

		\(onPath ? "@Instantiable" : "@Instantiable(generateDependencyTree: true)")
		public final class \(holder): Instantiable {
		    init(\(cartProperty), checkout: CheckoutScreen) {
		        self.\(cartLabel) = \(cartLabel)
		        self.checkout = checkout
		    }

		    @Instantiated private let \(cartProperty)
		    @Instantiated private let checkout: CheckoutScreen
		}
		"""
		let storeScreen = """
		import SafeDI

		@Instantiable(generateDependencyTree: true)
		public final class StoreScreen: Instantiable {
		    init(aisle: Aisle) {
		        self.aisle = aisle
		    }

		    @Instantiated private let aisle: Aisle
		}
		"""
		let paymentService = """
		import SafeDI
		import Core
		\(cartInCore ? "" : "import Store\n")
		@Instantiable(fulfillingAdditionalTypes: [PaymentService.self])
		\(fulfilledInStore ? "public " : "")final class LivePaymentService: PaymentService, Instantiable {
		    init(\(cartProperty)) {
		        self.\(cartLabel) = \(cartLabel)
		    }

		    @Received private let \(cartProperty)
		}
		"""
		let root = """
		import SafeDI
		import Store

		@Instantiable(isRoot: true)
		public final class Root: Instantiable {
		    public init(store: StoreScreen) {
		        self.store = store
		    }

		    @Instantiated private let store: StoreScreen
		}
		"""
		var storeFiles = [holderDeclaration]
		if onPath {
			storeFiles.append(storeScreen)
		}
		if !cartInCore {
			storeFiles.append(cart(isPublic: false))
		}
		if fulfilledInStore {
			storeFiles.append(paymentService)
		}
		return [
			ModuleFixture(name: "Core", packageName: "Shop", swiftFileContent: ["public protocol PaymentService {}"] + (cartInCore ? [cart(isPublic: true)] : [])),
			ModuleFixture(name: "Checkout", packageName: "Shop", swiftFileContent: [checkoutScreen], dependencies: ["Core"]),
			ModuleFixture(name: "Store", packageName: "Shop", swiftFileContent: storeFiles, dependencies: ["Core", "Checkout"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: (fulfilledInStore ? [] : [paymentService]) + [root], dependencies: ["Core", "Checkout", "Store"]),
		]
	}

	/// The shape with `CheckoutScreen` and `StoreScreen` both in `Store`.
	private static func shapeWithSeamsInOneModule() -> [ModuleFixture] {
		let modules = shape()
		return [
			modules[0],
			ModuleFixture(name: "Store", packageName: "Shop", swiftFileContent: modules[1].swiftFileContent + modules[2].swiftFileContent.map { $0.replacingOccurrences(of: "import Checkout\n", with: "") }, dependencies: ["Core"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: modules[3].swiftFileContent.map { $0.replacingOccurrences(of: "import Checkout\n", with: "") }, dependencies: ["Core", "Store"]),
		]
	}
}
