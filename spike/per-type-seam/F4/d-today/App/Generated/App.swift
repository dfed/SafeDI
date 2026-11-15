import Feature
import Harness
import SafeDI

extension Root {
    public convenience init() {
        func __safeDI_checkout() -> Checkout {
            func __safeDI_paymentsBuilder_Checkout() -> Checkout.SafeDIScope_Payments.__safeDI_Builder<any Payments> {
                func __safeDI_payments() -> any Payments {
                    func __safeDI_retryBuilder() -> Checkout {
                        Checkout(__safeDI_paymentsBuilder: __safeDI_paymentsBuilder_Checkout())
                    }
                    let retryBuilder = Instantiator<Checkout>(__safeDI_retryBuilder)
                    return LivePayments(cart: nil, retryBuilder: retryBuilder)
                }
                return .init(
                    payments: { _ in __safeDI_payments() },
                    cartScreenBuilder: { _ in __safeDI_paymentsBuilder_Checkout_CartScreen_Scope() }
                )
            }
            func __safeDI_paymentsBuilder_Checkout_CartScreen_Scope() -> Checkout.SafeDIScope_Payments.CartScreen_Scope.__safeDI_Builder<any Payments> {
                func __safeDI_payments(cart: Cart) -> any Payments {
                    func __safeDI_retryBuilder() -> Checkout {
                        Checkout(__safeDI_paymentsBuilder: __safeDI_paymentsBuilder_Checkout())
                    }
                    let retryBuilder = Instantiator<Checkout>(__safeDI_retryBuilder)
                    return LivePayments(cart: cart, retryBuilder: retryBuilder)
                }
                return .init(payments: { values in __safeDI_payments(cart: values.cart) })
            }
            return Checkout(__safeDI_paymentsBuilder: __safeDI_paymentsBuilder_Checkout())
        }
        let checkout: Checkout = __safeDI_checkout()
        self.init(checkout: checkout)
    }
}
