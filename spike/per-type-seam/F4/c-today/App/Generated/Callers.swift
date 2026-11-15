import Feature
import Harness
import SafeDI

// Hand-written callers of the readable initializer; they must compile unchanged against (c) and (d).
func handWrittenCallers() -> [Checkout] {
	[
		Checkout { LivePayments(cart: nil, retryBuilder: Instantiator { Checkout { LivePayments(cart: nil, retryBuilder: Instantiator { fatalError() }) } }) },
		Checkout(paymentsBuilder: { LivePayments(cart: Cart(), retryBuilder: Instantiator { fatalError() }) }),
	]
}
