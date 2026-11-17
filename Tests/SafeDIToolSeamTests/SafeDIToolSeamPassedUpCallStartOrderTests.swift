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

/// Where a seam starts its calls of inner seams whose places it passes up, against a sibling declared after them.
///
/// `Store`, a seam of `Feature`, declares `banner`, a call of the seam `Banner`, and `checkoutBuilder`, a call of the seam
/// `CheckoutScreen` behind an erased instantiator, before `cart`. Each inner seam instantiates `payments: any PaymentService`,
/// which no type `Feature` sees fulfills, so `Store` passes both places up and `App` fills them.
struct SafeDIToolSeamPassedUpCallStartOrderTests: ~Copyable {
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
	mutating func generate_startsPassedUpCallsAfterTheSiblingTheirFillReads_whenTheCallsAreDeclaredBeforeIt() async throws {
		// `App` fills both places with `LiveCart`, which receives `cart`. Inline, both calls wait for `cart`, so `cart` is
		// built first. A call that passes a place up starts after a sibling its fill reads that is declared after it: `Store`
		// builds `cart` first, binds the values its calls carry, then starts `banner` and `checkoutBuilder` in declaration
		// order, and `App` reads `cart` from the values each call carries.
		// W1g1: today the call starts in declaration order, before `cart`, and the fill's read of `cart` is rejected as a value
		// `Store` builds where it calls `Banner`. This test expects the graph accepted once a passed-up call starts after the
		// sibling its fill reads.
		await withKnownIssue("W1g1: a call that passes a place up starts before a sibling its fill reads that is declared after it") {
			let modules = Self.modules(feature: Self.feature, app: [Self.liveCart, Self.root])
			let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
			expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
				"Feature.swift": generatedFileHeader + """
				extension Banner {
				    @frozen nonisolated public enum SafeDIScope_PaymentService {
				        case payments(payments_Values)

				        nonisolated public struct payments_Values {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let payments: (payments_Values) -> __safeDI_Built

				            public init(payments: @escaping (payments_Values) -> __safeDI_Built) {
				                self.payments = payments
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.payments = { _ in __safeDI_builder() }
				            }
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_paymentServiceBuilder: SafeDIScope_PaymentService.__safeDI_Builder<any PaymentService>) {
				        let payments: any PaymentService = __safeDI_paymentServiceBuilder.payments(SafeDIScope_PaymentService.payments_Values())
				        self.init(payments: payments)
				    }
				}

				extension Banner {
				    public enum __safeDI_Banner_BBCEF4F117CBB63B {}
				}

				extension CheckoutScreen {
				    @frozen nonisolated public enum SafeDIScope_PaymentService {
				        case payments(payments_Values)

				        nonisolated public struct payments_Values {
				            public let id: Int
				        }

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let payments: (payments_Values) -> __safeDI_Built

				            public init(payments: @escaping (payments_Values) -> __safeDI_Built) {
				                self.payments = payments
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.payments = { _ in __safeDI_builder() }
				            }
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_id id: Int, __safeDI_paymentServiceBuilder: SafeDIScope_PaymentService.__safeDI_Builder<any PaymentService>) {
				        let payments: any PaymentService = __safeDI_paymentServiceBuilder.payments(SafeDIScope_PaymentService.payments_Values(id: id))
				        self.init(id: id, payments: payments)
				    }
				}

				extension CheckoutScreen {
				    public enum __safeDI_CheckoutScreen_EC77F97330AFD28B {}
				}

				extension Store {
				    @frozen public enum SafeDIScope_PaymentService {
				        case banner(__safeDI_Values, Banner.SafeDIScope_PaymentService)
				        case checkoutBuilder(__safeDI_Values, CheckoutScreen.SafeDIScope_PaymentService)

				        public struct __safeDI_Values {
				            public let cart: Cart
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_paymentServiceBuilder: @escaping (SafeDIScope_PaymentService) -> any PaymentService) {
				        let cart = Cart()
				        let __safeDI_paymentServiceValues = SafeDIScope_PaymentService.__safeDI_Values(cart: cart)
				        func __safeDI_banner() -> Banner {
				            _ = Banner.__safeDI_Banner_BBCEF4F117CBB63B.self
				            return Banner(__safeDI_paymentServiceBuilder: .init(payments: { __safeDI_paymentsValues in __safeDI_paymentServiceBuilder(.banner(__safeDI_paymentServiceValues, .payments(__safeDI_paymentsValues))) }))
				        }
				        let banner: Banner = __safeDI_banner()
				        func __safeDI_checkoutBuilder(id: Int) -> CheckoutScreen {
				            _ = CheckoutScreen.__safeDI_CheckoutScreen_EC77F97330AFD28B.self
				            return CheckoutScreen(__safeDI_id: id, __safeDI_paymentServiceBuilder: .init(payments: { __safeDI_paymentsValues in __safeDI_paymentServiceBuilder(.checkoutBuilder(__safeDI_paymentServiceValues, .payments(__safeDI_paymentsValues))) }))
				        }
				        let checkoutBuilder = ErasedInstantiator<Int, CheckoutScreen> {
				            __safeDI_checkoutBuilder(id: $0)
				        }
				        self.init(banner: banner, checkoutBuilder: checkoutBuilder, cart: cart)
				    }
				}

				extension Store {
				    public enum __safeDI_Store_CE17A76DE498638D {}
				}
				""",
			])
			expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public convenience init() {
				        func __safeDI_store() -> Store {
				            _ = Store.__safeDI_Store_CE17A76DE498638D.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            func __safeDI_paymentServiceBuilder_Store(_ scope: Store.SafeDIScope_PaymentService) -> any PaymentService {
				                switch scope {
				                case let .banner(values, scope): return __safeDI_paymentServiceBuilder_Banner(scope, cart: values.cart)
				                case let .checkoutBuilder(values, scope): return __safeDI_paymentServiceBuilder_CheckoutScreen(scope, cart: values.cart)
				                }
				            }
				            func __safeDI_paymentServiceBuilder_Banner(_ scope: Banner.SafeDIScope_PaymentService, cart: Cart) -> any PaymentService {
				                switch scope {
				                case .payments:
				                    let payments: any PaymentService = LiveCart(cart: cart)
				                    return payments
				                }
				            }
				            func __safeDI_paymentServiceBuilder_CheckoutScreen(_ scope: CheckoutScreen.SafeDIScope_PaymentService, cart: Cart) -> any PaymentService {
				                switch scope {
				                case .payments:
				                    let payments: any PaymentService = LiveCart(cart: cart)
				                    return payments
				                }
				            }
				            return Store(__safeDI_paymentServiceBuilder: __safeDI_paymentServiceBuilder_Store)
				        }
				        let store: Store = __safeDI_store()
				        self.init(store: store)
				    }
				}
				""",
			])
			try await expectValuesEqualInlineBuild(output, modules: modules, fulfiller: Self.liveCart)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_startsPassedUpCallsInDeclarationOrder_whenTheirFillReadsNoSiblingDeclaredAfterThem() async throws {
		// `App` fills both places with `LiveNothing`, which receives nothing. Inline builds `banner`, then `checkoutBuilder`,
		// then `cart`, in declaration order, and so does `Store`: a passed-up call starts after a later sibling only when its
		// fill reads that sibling.
		let modules = Self.modules(feature: Self.feature, app: [Self.liveNothing, Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
			"Feature.swift": generatedFileHeader + """
			extension Banner {
			    @frozen nonisolated public enum SafeDIScope_PaymentService {
			        case payments(payments_Values)

			        nonisolated public struct payments_Values {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let payments: (payments_Values) -> __safeDI_Built

			            public init(payments: @escaping (payments_Values) -> __safeDI_Built) {
			                self.payments = payments
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.payments = { _ in __safeDI_builder() }
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public convenience init(__safeDI_paymentServiceBuilder: SafeDIScope_PaymentService.__safeDI_Builder<any PaymentService>) {
			        let payments: any PaymentService = __safeDI_paymentServiceBuilder.payments(SafeDIScope_PaymentService.payments_Values())
			        self.init(payments: payments)
			    }
			}

			extension Banner {
			    public enum __safeDI_Banner_BBCEF4F117CBB63B {}
			}

			extension CheckoutScreen {
			    @frozen nonisolated public enum SafeDIScope_PaymentService {
			        case payments(payments_Values)

			        nonisolated public struct payments_Values {
			            public let id: Int
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let payments: (payments_Values) -> __safeDI_Built

			            public init(payments: @escaping (payments_Values) -> __safeDI_Built) {
			                self.payments = payments
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.payments = { _ in __safeDI_builder() }
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public convenience init(__safeDI_id id: Int, __safeDI_paymentServiceBuilder: SafeDIScope_PaymentService.__safeDI_Builder<any PaymentService>) {
			        let payments: any PaymentService = __safeDI_paymentServiceBuilder.payments(SafeDIScope_PaymentService.payments_Values(id: id))
			        self.init(id: id, payments: payments)
			    }
			}

			extension CheckoutScreen {
			    public enum __safeDI_CheckoutScreen_EC77F97330AFD28B {}
			}

			extension Store {
			    @frozen public enum SafeDIScope_PaymentService {
			        case banner(Banner.SafeDIScope_PaymentService)
			        case checkoutBuilder(CheckoutScreen.SafeDIScope_PaymentService)
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public convenience init(__safeDI_paymentServiceBuilder: @escaping (SafeDIScope_PaymentService) -> any PaymentService) {
			        func __safeDI_banner() -> Banner {
			            _ = Banner.__safeDI_Banner_BBCEF4F117CBB63B.self
			            return Banner(__safeDI_paymentServiceBuilder: .init(payments: { __safeDI_paymentsValues in __safeDI_paymentServiceBuilder(.banner(.payments(__safeDI_paymentsValues))) }))
			        }
			        let banner: Banner = __safeDI_banner()
			        func __safeDI_checkoutBuilder(id: Int) -> CheckoutScreen {
			            _ = CheckoutScreen.__safeDI_CheckoutScreen_EC77F97330AFD28B.self
			            return CheckoutScreen(__safeDI_id: id, __safeDI_paymentServiceBuilder: .init(payments: { __safeDI_paymentsValues in __safeDI_paymentServiceBuilder(.checkoutBuilder(.payments(__safeDI_paymentsValues))) }))
			        }
			        let checkoutBuilder = ErasedInstantiator<Int, CheckoutScreen> {
			            __safeDI_checkoutBuilder(id: $0)
			        }
			        let cart = Cart()
			        self.init(banner: banner, checkoutBuilder: checkoutBuilder, cart: cart)
			    }
			}

			extension Store {
			    public enum __safeDI_Store_CE17A76DE498638D {}
			}
			""",
		])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public convenience init() {
			        func __safeDI_store() -> Store {
			            _ = Store.__safeDI_Store_CE17A76DE498638D.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_paymentServiceBuilder_Store(_ scope: Store.SafeDIScope_PaymentService) -> any PaymentService {
			                switch scope {
			                case let .banner(scope): return __safeDI_paymentServiceBuilder_Banner(scope)
			                case let .checkoutBuilder(scope): return __safeDI_paymentServiceBuilder_CheckoutScreen(scope)
			                }
			            }
			            func __safeDI_paymentServiceBuilder_Banner(_ scope: Banner.SafeDIScope_PaymentService) -> any PaymentService {
			                switch scope {
			                case .payments:
			                    let payments: any PaymentService = LiveNothing()
			                    return payments
			                }
			            }
			            func __safeDI_paymentServiceBuilder_CheckoutScreen(_ scope: CheckoutScreen.SafeDIScope_PaymentService) -> any PaymentService {
			                switch scope {
			                case .payments:
			                    let payments: any PaymentService = LiveNothing()
			                    return payments
			                }
			            }
			            return Store(__safeDI_paymentServiceBuilder: __safeDI_paymentServiceBuilder_Store)
			        }
			        let store: Store = __safeDI_store()
			        self.init(store: store)
			    }
			}
			""",
		])
		try await expectValuesEqualInlineBuild(output, modules: modules, fulfiller: Self.liveNothing)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Feature`: `Store` calls `Banner` and, behind an erased instantiator, `CheckoutScreen`, each a seam whose place
	/// `payments` `Store` passes up, and then instantiates `cart`.
	private static let feature = [
		"public protocol PaymentService {}",
		seamFixtureType(named: "Cart", isFinalClass: true, declarations: []),
		seamFixtureType(named: "Banner", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let payments: any PaymentService"]),
		seamFixtureType(named: "CheckoutScreen", isSeam: true, isFinalClass: true, declarations: ["@Forwarded let id: Int", "@Instantiated let payments: any PaymentService"]),
		seamFixtureType(named: "Store", isSeam: true, isFinalClass: true, declarations: [
			"@Instantiated let banner: Banner",
			#"@Instantiated(fulfilledByType: "CheckoutScreen") let checkoutBuilder: ErasedInstantiator<Int, CheckoutScreen>"#,
			"@Instantiated let cart: Cart",
		]),
	]

	/// A fulfiller of `PaymentService` that receives `Store`'s `cart`.
	private static let liveCart = SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveCart", fulfilling: "PaymentService", declarations: ["@Received let cart: Cart"])

	/// A fulfiller of `PaymentService` that receives nothing.
	private static let liveNothing = SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveNothing", fulfilling: "PaymentService", declarations: [])

	private static let root = seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let store: Store"])

	private static func modules(feature: [String], app: [String]) -> [ModuleFixture] {
		SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app)
	}

	/// Expects the values `output`, the run of `modules`, builds for `Root()`, and for a store beside a screen its
	/// instantiator builds, to equal those of the same graph with `fulfiller` declared in `Feature`, where `Store` fills both places
	/// itself and every tree is built inline.
	private mutating func expectValuesEqualInlineBuild(
		_ output: MultiModuleTestOutput,
		modules: [ModuleFixture],
		fulfiller: String,
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		guard compileVerificationIsEnabled else { return }
		let inlineModules = Self.modules(feature: Self.feature + [fulfiller], app: [Self.root])
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: DifferentialValuePath(output: output, modules: modules),
			knownRight: DifferentialValuePath(output: inlineOutput, modules: inlineModules),
			probes: [
				DifferentialValueProbe("Root()"),
				DifferentialValueProbe("{ () -> (Store, CheckoutScreen) in let store = Root().store; return (store, store.checkoutBuilder.instantiate(2)) }()"),
			],
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	/// Expects `generatedFiles` to equal `expected`, recording the files generated when they do not, so a failure shows
	/// the output in full.
	private func expectGeneratedFiles(_ generatedFiles: [String: String]?, _ expected: [String: String], sourceLocation: SourceLocation = #_sourceLocation) {
		#expect(generatedFiles == expected, sourceLocation: sourceLocation)
		if let generatedFiles, generatedFiles != expected {
			Issue.record(Comment(rawValue: generatedFiles.sorted { $0.key < $1.key }.map { "=== \($0.key)\n\($0.value)" }.joined(separator: "\n")), sourceLocation: sourceLocation)
		}
	}
}
