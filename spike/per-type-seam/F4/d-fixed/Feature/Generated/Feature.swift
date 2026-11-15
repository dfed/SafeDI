import Harness
import SafeDI

extension Checkout {
    nonisolated public enum SafeDIScope_Payments {
        nonisolated public struct payments_Values {}

        nonisolated public struct cartScreenBuilder_Values {
            public let payments: any Payments
        }

        nonisolated public struct __safeDI_Builder<Built> {
            public let payments: (payments_Values) -> Built
            public let cartScreenBuilder: (cartScreenBuilder_Values) -> CartScreen_Scope.__safeDI_Builder<Built>

            public init(payments: @escaping (payments_Values) -> Built, cartScreenBuilder: @escaping (cartScreenBuilder_Values) -> CartScreen_Scope.__safeDI_Builder<Built>) {
                self.payments = payments
                self.cartScreenBuilder = cartScreenBuilder
            }

            public init(__safeDI_noScope builder: @escaping () -> Built) {
                payments = { _ in builder() }
                cartScreenBuilder = { _ in .init(__safeDI_noScope: builder) }
            }
        }

        nonisolated public enum CartScreen_Scope {
            nonisolated public struct payments_Values {
                public let cart: Cart
            }

            nonisolated public struct __safeDI_Builder<Built> {
                public let payments: (payments_Values) -> Built

                public init(payments: @escaping (payments_Values) -> Built) {
                    self.payments = payments
                }

                public init(__safeDI_noScope builder: @escaping () -> Built) {
                    payments = { _ in builder() }
                }
            }
        }
    }

    /// For code you write.
    public convenience init(paymentsBuilder: @escaping () -> any Payments) {
        self.init(__safeDI_paymentsBuilder: .init(__safeDI_noScope: paymentsBuilder))
    }

    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
    public convenience init(__safeDI_paymentsBuilder: SafeDIScope_Payments.__safeDI_Builder<any Payments>) {
        func __safeDI_cartScreen(_ __safeDI_paymentsBuilder: SafeDIScope_Payments.CartScreen_Scope.__safeDI_Builder<any Payments>, cart: Cart) -> CartScreen {
            let payments: any Payments = __safeDI_paymentsBuilder.payments(.init(cart: cart))
            return CartScreen(cart: cart, payments: payments)
        }
        let payments: any Payments = __safeDI_paymentsBuilder.payments(.init())
        let __safeDI_paymentsBuilder_cartScreenBuilder = __safeDI_paymentsBuilder.cartScreenBuilder(.init(payments: payments))
        let cartScreenBuilder = Instantiator<CartScreen> {
            __safeDI_cartScreen(__safeDI_paymentsBuilder_cartScreenBuilder, cart: $0)
        }
        self.init(payments: payments, cartScreenBuilder: cartScreenBuilder)
    }
}
