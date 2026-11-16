"""Authored once: run.sh does not rerun it, since ./CLI/lint.sh formats what it wrote and the formatted files are committed.
Writes F4's hand-written variants: (c) the leak fix's per-path body and (d) the per-type body, each with the calling
module's code as the leak fix would emit it today (`-today`: the root level function takes no parameter, as today's
root dispatcher) and with the hypothesis (`-fixed`: the root level function takes `cart: Cart?`, which `Root` passes
`nil` and the re-entry from `CartScreen_Scope` passes the screen's `cart`)."""
import os

STRUCTS = """import Harness
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

"""

PER_PATH = """    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
    public convenience init(__safeDI_paymentsBuilder: SafeDIScope_Payments.__safeDI_Builder<any Payments>) {
        let payments: any Payments = __safeDI_paymentsBuilder.payments(.init())
        let __safeDI_paymentsBuilder_cartScreenBuilder = __safeDI_paymentsBuilder.cartScreenBuilder(.init(payments: payments))
        func __safeDI_cartScreenBuilder(cart: Cart) -> CartScreen {
            let payments: any Payments = __safeDI_paymentsBuilder_cartScreenBuilder.payments(.init(cart: cart))
            return CartScreen(cart: cart, payments: payments)
        }
        let cartScreenBuilder = Instantiator<CartScreen> {
            __safeDI_cartScreenBuilder(cart: $0)
        }
        self.init(payments: payments, cartScreenBuilder: cartScreenBuilder)
    }
}
"""

PER_TYPE = """    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
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
"""


def app(fixed):
    root_parameters = "cart: Cart?" if fixed else ""
    root_call_from_root = "__safeDI_paymentsBuilder_Checkout(cart: nil)" if fixed else "__safeDI_paymentsBuilder_Checkout()"
    reenter_from_root = "__safeDI_paymentsBuilder_Checkout(cart: cart)" if fixed else "__safeDI_paymentsBuilder_Checkout()"
    reenter_from_screen = "__safeDI_paymentsBuilder_Checkout(cart: cart)" if fixed else "__safeDI_paymentsBuilder_Checkout()"
    root_cart = "cart" if fixed else "nil"
    return f"""import Feature
import Harness
import SafeDI

extension Root {{
    public convenience init() {{
        func __safeDI_checkout() -> Checkout {{
            func __safeDI_paymentsBuilder_Checkout({root_parameters}) -> Checkout.SafeDIScope_Payments.__safeDI_Builder<any Payments> {{
                func __safeDI_payments() -> any Payments {{
                    func __safeDI_retryBuilder() -> Checkout {{
                        Checkout(__safeDI_paymentsBuilder: {reenter_from_root})
                    }}
                    let retryBuilder = Instantiator<Checkout>(__safeDI_retryBuilder)
                    return LivePayments(cart: {root_cart}, retryBuilder: retryBuilder)
                }}
                return .init(
                    payments: {{ _ in __safeDI_payments() }},
                    cartScreenBuilder: {{ _ in __safeDI_paymentsBuilder_Checkout_CartScreen_Scope() }}
                )
            }}
            func __safeDI_paymentsBuilder_Checkout_CartScreen_Scope() -> Checkout.SafeDIScope_Payments.CartScreen_Scope.__safeDI_Builder<any Payments> {{
                func __safeDI_payments(cart: Cart) -> any Payments {{
                    func __safeDI_retryBuilder() -> Checkout {{
                        Checkout(__safeDI_paymentsBuilder: {reenter_from_screen})
                    }}
                    let retryBuilder = Instantiator<Checkout>(__safeDI_retryBuilder)
                    return LivePayments(cart: cart, retryBuilder: retryBuilder)
                }}
                return .init(payments: {{ values in __safeDI_payments(cart: values.cart) }})
            }}
            return Checkout(__safeDI_paymentsBuilder: {root_call_from_root})
        }}
        let checkout: Checkout = __safeDI_checkout()
        self.init(checkout: checkout)
    }}
}}
"""


CALLERS = """import Feature
import Harness
import SafeDI

// Hand-written callers of the readable initializer; they must compile unchanged against (c) and (d).
func handWrittenCallers() -> [Checkout] {
    [
        Checkout { LivePayments(cart: nil, retryBuilder: Instantiator { Checkout { LivePayments(cart: nil, retryBuilder: Instantiator { fatalError() }) } }) },
        Checkout(paymentsBuilder: { LivePayments(cart: Cart(), retryBuilder: Instantiator { fatalError() }) }),
    ]
}
"""


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as file:
        file.write(text)


for body_name, body in [("c", PER_PATH), ("d", PER_TYPE)]:
    for caller in ["today", "fixed"]:
        variant = f"{body_name}-{caller}"
        write(f"{variant}/modules.txt", "Harness plain\nFeature hand Harness\nApp hand Feature Harness\nMain plain App Harness\n")
        write(f"{variant}/Harness/shared", "../common\n")
        write(f"{variant}/Feature/shared", "shared/Feature\n")
        write(f"{variant}/App/shared", "shared/App\n")
        write(f"{variant}/Main/shared", "main\n")
        write(f"{variant}/Feature/Generated/Feature.swift", STRUCTS + body)
        write(f"{variant}/App/Generated/App.swift", app(caller == "fixed"))
        write(f"{variant}/App/Generated/Callers.swift", CALLERS)
