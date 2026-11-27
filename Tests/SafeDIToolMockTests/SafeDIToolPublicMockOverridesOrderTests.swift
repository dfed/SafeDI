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

/// A public mock's `SafeDIOverrides`, and each configuration it nests, takes its members in the inline build's order:
/// declaration order, each child after the siblings it receives. The mock's body builds a child that holds one of the
/// mock's places after its siblings, so that the place's scope struct carries them, but that build order never reaches the
/// initializer a person calls, which stays the order of the same types' internal mock.
struct SafeDIToolPublicMockOverridesOrderTests: ~Copyable {
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
	mutating func mock_takesOverridesInDeclarationOrder_whenSameModuleSeamDeclaredFirstHoldsAPlace() async throws {
		// `banner`, a seam of the same module whose place the mock builds, is built after `db` and `cart`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [ModuleFixture(name: "Feature", packageName: "feature", swiftFileContent: [Self.store])],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)

		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Banner {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_PaymentServiceCarrier<__safeDI_Built> {
		        public let payments: () -> __safeDI_Built

		        public init(payments: @escaping () -> __safeDI_Built) {
		            self.payments = payments
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(payments: { __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_paymentServiceBuilder: __safeDI_PaymentServiceCarrier<any PaymentService>) {
		        let payments: any PaymentService = __safeDI_paymentServiceBuilder.payments()
		        self.init(payments: payments)
		    }
		}

		extension Banner {
		    public enum __safeDI_Banner_A99D80A9F942B3F9 {}
		}

		#if DEBUG
		extension Store {
		    nonisolated public enum SafeDIMockScope_PaymentService {
		        nonisolated public struct banner_Values {
		            public let db: Db
		            public let cart: Cart
		        }

		        nonisolated public enum Banner_Scope {
		            nonisolated public struct payments_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let payments: (payments_Values) -> __safeDI_Built

		                public init(payments: @escaping (payments_Values) -> __safeDI_Built) {
		                    self.payments = payments
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(payments: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let banner: (banner_Values) -> SafeDIMockScope_PaymentService.Banner_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(banner: @escaping (banner_Values) -> SafeDIMockScope_PaymentService.Banner_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.banner = banner
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(banner: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            banner: ((any PaymentService) -> Banner)? = nil,
		            db: (() -> Db)? = nil,
		            cart: ((Db) -> Cart)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                banner: banner,
		                db: db,
		                cart: cart
		            )
		        }

		        public var banner: ((any PaymentService) -> Banner)? { __safeDI_storage.banner }
		        public var db: (() -> Db)? { __safeDI_storage.db }
		        public var cart: ((Db) -> Cart)? { __safeDI_storage.cart }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                banner: ((any PaymentService) -> Banner)?,
		                db: (() -> Db)?,
		                cart: ((Db) -> Cart)?
		            ) {
		                self.banner = banner
		                self.db = db
		                self.cart = cart
		            }

		            let banner: ((any PaymentService) -> Banner)?
		            let db: (() -> Db)?
		            let cart: ((Db) -> Cart)?
		        }
		    }

		    public static func mock(
		        paymentServiceBuilder: @escaping () -> any PaymentService,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Store {
		        Store.__safeDI_mock(paymentServiceBuilder: .init(__safeDI_noScope: paymentServiceBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        paymentServiceBuilder __safeDI_paymentServiceBuilder: Store.SafeDIMockScope_PaymentService.__safeDI_Builder<any PaymentService>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Store {
		        let db = if let safeDIBuilder = safeDIOverrides.db { safeDIBuilder() } else { Db() }
		        let cart = if let safeDIBuilder = safeDIOverrides.cart { safeDIBuilder(db) } else { Cart(db: db) }
		        let __safeDI_paymentServiceBuilder_banner = __safeDI_paymentServiceBuilder.banner(SafeDIMockScope_PaymentService.banner_Values(db: db, cart: cart))
		        func __safeDI_banner() -> Banner {
		            let payments: any PaymentService = __safeDI_paymentServiceBuilder_banner.payments(SafeDIMockScope_PaymentService.Banner_Scope.payments_Values())
		            return if let safeDIBuilder = safeDIOverrides.banner { safeDIBuilder(payments) } else { Banner(payments: payments) }
		        }
		        let banner: Banner = __safeDI_banner()
		        return Store(banner: banner, db: db, cart: cart)
		    }
		}

		extension Store {
		    public enum __safeDI_Store_mock_9615661BDF20113C {}
		}
		#endif
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_takesOverridesInDeclarationOrder_whenChildDeclaredBesideCalledPublicMockHoldsAPlace() async throws {
		// `own` holds a place of the mock and is built after `b` and `c`; `inner` calls `Core`'s public mock, which passes
		// its place up.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "core", swiftFileContent: [Self.inner]),
				ModuleFixture(name: "App", packageName: "app", swiftFileContent: [Self.parent], dependencies: ["Core"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)

		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Parent {
		    nonisolated public enum SafeDIMockScope_Gadget {
		        nonisolated public struct own_Values {
		            public let inner: Inner
		            public let b: B
		            public let c: C
		        }

		        nonisolated public enum Own_Scope {
		            nonisolated public struct gadget_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let gadget: (gadget_Values) -> __safeDI_Built

		                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
		                    self.gadget = gadget
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(gadget: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let own: (own_Values) -> SafeDIMockScope_Gadget.Own_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(own: @escaping (own_Values) -> SafeDIMockScope_Gadget.Own_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.own = own
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(own: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    nonisolated public enum SafeDIMockScope_Service {
		        nonisolated public struct inner_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let inner: (inner_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>

		            public init(inner: @escaping (inner_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<__safeDI_Built>) {
		                self.inner = inner
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(inner: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            inner: Inner.SafeDIOverrides = .init(),
		            own: ((any Gadget) -> Own)? = nil,
		            b: (() -> B)? = nil,
		            c: ((B) -> C)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                inner: inner,
		                own: own,
		                b: b,
		                c: c
		            )
		        }

		        public var inner: Inner.SafeDIOverrides { __safeDI_storage.inner }
		        public var own: ((any Gadget) -> Own)? { __safeDI_storage.own }
		        public var b: (() -> B)? { __safeDI_storage.b }
		        public var c: ((B) -> C)? { __safeDI_storage.c }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                inner: Inner.SafeDIOverrides,
		                own: ((any Gadget) -> Own)?,
		                b: (() -> B)?,
		                c: ((B) -> C)?
		            ) {
		                self.inner = inner
		                self.own = own
		                self.b = b
		                self.c = c
		            }

		            let inner: Inner.SafeDIOverrides
		            let own: ((any Gadget) -> Own)?
		            let b: (() -> B)?
		            let c: ((B) -> C)?
		        }
		    }

		    public static func mock(
		        gadgetBuilder: @escaping () -> any Gadget,
		        serviceBuilder: @escaping () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Parent {
		        Parent.__safeDI_mock(gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder), serviceBuilder: .init(__safeDI_noScope: serviceBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        gadgetBuilder __safeDI_gadgetBuilder: Parent.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>,
		        serviceBuilder __safeDI_serviceBuilder: Parent.SafeDIMockScope_Service.__safeDI_Builder<any Service>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Parent {
		        _ = Inner.__safeDI_Inner_mock_617F330920A5370E.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let inner = Inner.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.inner(SafeDIMockScope_Service.inner_Values()), safeDIOverrides: safeDIOverrides.inner)
		        let b = if let safeDIBuilder = safeDIOverrides.b { safeDIBuilder() } else { B() }
		        let c = if let safeDIBuilder = safeDIOverrides.c { safeDIBuilder(b) } else { C(b: b) }
		        let __safeDI_gadgetBuilder_own = __safeDI_gadgetBuilder.own(SafeDIMockScope_Gadget.own_Values(inner: inner, b: b, c: c))
		        func __safeDI_own() -> Own {
		            let gadget: any Gadget = __safeDI_gadgetBuilder_own.gadget(SafeDIMockScope_Gadget.Own_Scope.gadget_Values())
		            return if let safeDIBuilder = safeDIOverrides.own { safeDIBuilder(gadget) } else { Own(gadget: gadget) }
		        }
		        let own: Own = __safeDI_own()
		        return Parent(inner: inner, own: own, b: b, c: c)
		    }
		}

		extension Parent {
		    public enum __safeDI_Parent_mock_E529B684C7E4DD63 {}
		}
		#endif
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_takesNestedConfigurationInDeclarationOrder_whenChildBeneathMockedTypeHoldsAPlace() async throws {
		// `Shelf`'s `own` holds a place of the mock and is built after `b` and `c`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [ModuleFixture(name: "App", packageName: "app", swiftFileContent: [Self.parentOfShelf])],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)

		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Parent {
		    nonisolated public enum SafeDIMockScope_Gadget {
		        nonisolated public struct shelf_Values {}

		        nonisolated public enum Shelf_Scope {
		            nonisolated public struct own_Values {
		                public let b: B
		                public let c: C
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let own: (own_Values) -> SafeDIMockScope_Gadget.Own_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(own: @escaping (own_Values) -> SafeDIMockScope_Gadget.Own_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.own = own
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(own: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum Own_Scope {
		            nonisolated public struct gadget_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let gadget: (gadget_Values) -> __safeDI_Built

		                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
		                    self.gadget = gadget
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(gadget: { _ in __safeDI_builder() })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let shelf: (shelf_Values) -> SafeDIMockScope_Gadget.Shelf_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(shelf: @escaping (shelf_Values) -> SafeDIMockScope_Gadget.Shelf_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.shelf = shelf
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(shelf: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            shelf: __safeDI_App_Shelf_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                shelf: shelf
		            )
		        }

		        public var shelf: __safeDI_App_Shelf_MockConfiguration { __safeDI_storage.shelf }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                shelf: __safeDI_App_Shelf_MockConfiguration
		            ) {
		                self.shelf = shelf
		            }

		            let shelf: __safeDI_App_Shelf_MockConfiguration
		        }
		    }

		    public static func mock(
		        gadgetBuilder: @escaping () -> any Gadget,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Parent {
		        Parent.__safeDI_mock(gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        gadgetBuilder __safeDI_gadgetBuilder: Parent.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Parent {
		        let __safeDI_gadgetBuilder_shelf = __safeDI_gadgetBuilder.shelf(SafeDIMockScope_Gadget.shelf_Values())
		        func __safeDI_shelf() -> Shelf {
		            let b = if let safeDIBuilder = safeDIOverrides.shelf.b { safeDIBuilder() } else { B() }
		            let c = if let safeDIBuilder = safeDIOverrides.shelf.c { safeDIBuilder(b) } else { C(b: b) }
		            let __safeDI_gadgetBuilder_own = __safeDI_gadgetBuilder_shelf.own(SafeDIMockScope_Gadget.Shelf_Scope.own_Values(b: b, c: c))
		            func __safeDI_own() -> Own {
		                let gadget: any Gadget = __safeDI_gadgetBuilder_own.gadget(SafeDIMockScope_Gadget.Own_Scope.gadget_Values())
		                return if let safeDIBuilder = safeDIOverrides.shelf.own { safeDIBuilder(gadget) } else { Own(gadget: gadget) }
		            }
		            let own: Own = __safeDI_own()
		            return Shelf.__safeDI_init(own: own, b: b, c: c, safeDIBuilder: safeDIOverrides.shelf.safeDIBuilder)
		        }
		        let shelf: Shelf = __safeDI_shelf()
		        return Parent(shelf: shelf)
		    }
		}

		extension Parent {
		    public enum __safeDI_Parent_mock_FD2FAFEFF3ECDBC8 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Shelf` is constructed within the public mock trees of module `App`.
		nonisolated public struct __safeDI_App_Shelf_MockConfiguration {
		    public init(
		        own: ((any Gadget) -> Own)? = nil,
		        b: (() -> B)? = nil,
		        c: ((B) -> C)? = nil,
		        _ safeDIBuilder: ((Own, B, C) -> Shelf)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            own: own,
		            b: b,
		            c: c,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var own: ((any Gadget) -> Own)? { __safeDI_storage.own }
		    public var b: (() -> B)? { __safeDI_storage.b }
		    public var c: ((B) -> C)? { __safeDI_storage.c }
		    /// Overrides how `Shelf` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Own, B, C) -> Shelf)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            own: ((any Gadget) -> Own)?,
		            b: (() -> B)?,
		            c: ((B) -> C)?,
		            safeDIBuilder: ((Own, B, C) -> Shelf)?
		        ) {
		            self.own = own
		            self.b = b
		            self.c = c
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let own: ((any Gadget) -> Own)?
		        let b: (() -> B)?
		        let c: ((B) -> C)?
		        let safeDIBuilder: ((Own, B, C) -> Shelf)?
		    }
		}

		extension Shelf {
		    static func __safeDI_init(own: Own, b: B, c: C, safeDIBuilder: ((Own, B, C) -> Shelf)?) -> Shelf {
		        if let safeDIBuilder { safeDIBuilder(own, b, c) } else { Shelf(own: own, b: b, c: c) }
		    }
		}
		#endif

		""")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Store`, whose public mock builds `Banner`, a seam of the same module whose place the mock takes a builder for,
	/// declared before `db` and `cart`, which receives `db`.
	private static let store = """
	import SafeDI

	public protocol PaymentService {}

	@Instantiable(generateMock: .public)
	public final class Store: Instantiable {
	    public init(banner: Banner, db: Db, cart: Cart) {
	        self.banner = banner
	        self.db = db
	        self.cart = cart
	    }

	    @Instantiated let banner: Banner
	    @Instantiated let db: Db
	    @Instantiated let cart: Cart
	}

	@Instantiable(generateDependencyTree: true)
	public final class Banner: Instantiable {
	    public init(payments: any PaymentService) {
	        self.payments = payments
	    }

	    @Instantiated let payments: any PaymentService
	}

	@Instantiable
	public final class Db: Instantiable {
	    public init() {}
	}

	@Instantiable
	public final class Cart: Instantiable {
	    public init(db: Db) {
	        self.db = db
	    }

	    @Received let db: Db
	}
	"""

	/// `Inner`, whose public mock holds a place of `Service`, and whose initializer is `internal`, so a mock in another
	/// module calls its public mock.
	private static let inner = """
	import SafeDI

	public protocol Service {}

	@Instantiable(generateMock: .public)
	public final class Inner: Instantiable {
	    init(service: any Service, leaf: InnerLeaf) {
	        self.service = service
	        self.leaf = leaf
	    }

	    @Instantiated let service: any Service
	    @Instantiated let leaf: InnerLeaf
	}

	@Instantiable
	public final class InnerLeaf: Instantiable {
	    public init() {}
	}
	"""

	/// `Parent`, whose public mock calls `Inner`'s and builds `own`, which holds a place of the mock, declared before `b`
	/// and `c`, which receives `b`.
	private static let parent = """
	import Core
	import SafeDI

	public protocol Gadget {}

	@Instantiable(generateMock: .public)
	public final class Parent: Instantiable {
	    public init(inner: Inner, own: Own, b: B, c: C) {
	        self.inner = inner
	        self.own = own
	        self.b = b
	        self.c = c
	    }

	    @Instantiated let inner: Inner
	    @Instantiated let own: Own
	    @Instantiated let b: B
	    @Instantiated let c: C
	}

	\(ownBC)
	"""

	/// `Parent`, whose public mock builds `Shelf`, which declares `own`, holding a place of the mock, before `b` and `c`,
	/// which receives `b`.
	private static let parentOfShelf = """
	import SafeDI

	public protocol Gadget {}

	@Instantiable(generateMock: .public)
	public final class Parent: Instantiable {
	    public init(shelf: Shelf) {
	        self.shelf = shelf
	    }

	    @Instantiated let shelf: Shelf
	}

	@Instantiable
	public final class Shelf: Instantiable {
	    public init(own: Own, b: B, c: C) {
	        self.own = own
	        self.b = b
	        self.c = c
	    }

	    @Instantiated let own: Own
	    @Instantiated let b: B
	    @Instantiated let c: C
	}

	\(ownBC)
	"""

	/// `Own`, which holds a place of `Gadget`; `B`; and `C`, which receives `b`.
	private static let ownBC = """
	@Instantiable
	public final class Own: Instantiable {
	    public init(gadget: any Gadget) {
	        self.gadget = gadget
	    }

	    @Instantiated let gadget: any Gadget
	}

	@Instantiable
	public final class B: Instantiable {
	    public init() {}
	}

	@Instantiable
	public final class C: Instantiable {
	    public init(b: B) {
	        self.b = b
	    }

	    @Received let b: B
	}
	"""
}
