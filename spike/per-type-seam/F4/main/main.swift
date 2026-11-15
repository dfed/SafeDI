import App
#if canImport(Feature)
import Feature
#endif
import Harness

// Opens the cart screen with a cart, then retries: the second Checkout's `LivePayments` should receive that cart.
do {
	let root = Root()
	let cart = Cart()
	let screen = root.checkout.cartScreenBuilder.instantiate(cart)
	let retry = (screen.payments as! LivePayments).retryBuilder.instantiate()
	let retryScreen = retry.cartScreenBuilder.instantiate(Cart())
	print("trace:")
	Registry.printTrace()
	withExtendedLifetime((root, screen, retry, retryScreen)) {}
}
Registry.printAlive("after dropping everything")
// Holds only the retried Checkout: inline frees the cart screen, and keeps the cart only if a value holds it.
do {
	let retry: Checkout
	do {
		let root = Root()
		retry = (root.checkout.cartScreenBuilder.instantiate(Cart()).payments as! LivePayments).retryBuilder.instantiate()
	}
	Registry.printTrace()
	Registry.printAlive("holding only the retried Checkout")
	withExtendedLifetime(retry) {}
}
Registry.printAlive("after dropping the retried Checkout")
