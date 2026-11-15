"""F4, a `nil` value under a reopened seam: LivePayments's retryBuilder re-enters Checkout from inside CartScreen."""
import os
import sys

sys.path.insert(0, sys.argv[1])
from typegen import swift_type, write_module  # noqa: E402

cart = """public final class Cart: Traced {
    public init() {
        Registry.created(self, [:])
    }

    public let tracker = Tracker("Cart")
}

"""
feature = [
    swift_type("Checkout", [("inst", "payments", "any Payments"), ("inst", "cartScreenBuilder", "Instantiator<CartScreen>")], seam=True),
    swift_type("CartScreen", [("fwd", "cart", "Cart"), ("inst", "payments", "any Payments")]),
]
app = [
    swift_type("LivePayments", [("opt", "cart", "Cart?"), ("inst", "retryBuilder", "Instantiator<Checkout>")], fulfills="Payments"),
    swift_type("Root", [("inst", "checkout", "Checkout")], root=True),
]
protocol = "public protocol Payments: AnyObject {}\n\n"
configuration = "#SafeDIConfiguration(generatePlainDependencyTreeInitializers: true)\n\n"
write_module("shared/Feature", ["Harness", "SafeDI"], feature, cart + protocol + configuration)
write_module("shared/App", ["Feature", "Harness", "SafeDI"], app)
inline = [t.replace("(generateDependencyTree: true)", "") for t in feature]
write_module("shared/Inline", ["Harness", "SafeDI"], inline + app, cart + protocol)
os.makedirs("main", exist_ok=True)
with open("main/main.swift", "w") as file:
    file.write("""import App
#if canImport(Feature)
import Feature
#endif
import Harness

// Opens the cart screen with a cart, then retries: the second Checkout's `LivePayments` should receive that cart.
do {
\tlet root = Root()
\tlet cart = Cart()
\tlet screen = root.checkout.cartScreenBuilder.instantiate(cart)
\tlet retry = (screen.payments as! LivePayments).retryBuilder.instantiate()
\tlet retryScreen = retry.cartScreenBuilder.instantiate(Cart())
\tprint("trace:")
\tRegistry.printTrace()
\twithExtendedLifetime((root, screen, retry, retryScreen)) {}
}
Registry.printAlive("after dropping everything")
// Holds only the retried Checkout: inline frees the cart screen, and keeps the cart only if a value holds it.
do {
\tlet retry: Checkout
\tdo {
\t\tlet root = Root()
\t\tretry = (root.checkout.cartScreenBuilder.instantiate(Cart()).payments as! LivePayments).retryBuilder.instantiate()
\t}
\tRegistry.printTrace()
\tRegistry.printAlive("holding only the retried Checkout")
\twithExtendedLifetime(retry) {}
}
Registry.printAlive("after dropping the retried Checkout")
""")
