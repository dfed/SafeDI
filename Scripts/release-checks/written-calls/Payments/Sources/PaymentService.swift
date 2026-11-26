// From the manual’s “Public mocks”: a public mock with a `public` tier and a `package` tier, a default-valued
// initializer parameter, a lazily instantiated received dependency, and a type in its tree with a default-valued
// parameter of its own. (The manual names the type `Service` and its `package` dependency `Session`.)
import Core
import SafeDI

@Instantiable(generateMock: .public)
public struct PaymentService: Instantiable {
	package init(analytics: LazilyInstantiated<Analytics>, session: PaymentSession, tokenCache: TokenCache, retries: Int = 3) {
		self.analytics = analytics
		self.session = session
		self.tokenCache = tokenCache
		self.retries = retries
	}

	@Received private let analytics: LazilyInstantiated<Analytics>
	@Received private let session: PaymentSession // `PaymentSession` is `package`.
	@Instantiated private let tokenCache: TokenCache
	private let retries: Int
}

@Instantiable
package final class PaymentSession: Instantiable {
	package init() {}
}

@Instantiable
public final class TokenCache: Instantiable {
	public init(capacity: Int = 10) {
		self.capacity = capacity
	}

	private let capacity: Int
}

/// “Public mocks”: an `@autoclosure` default-valued parameter becomes `(() -> Int)? = nil` on a public mock.
@Instantiable(generateMock: .public)
public final class Poller: Instantiable {
	public init(interval: @autoclosure () -> Int = 3) {
		self.interval = interval()
	}

	private let interval: Int
}

/// “Dependency kinds in the generated mock”: a public mock of a type that instantiates, only if available, a dependency
/// a declaration fulfills takes the entry that binds it to `nil` too.
public protocol ReceiptPrinter {}

@Instantiable(fulfillingAdditionalTypes: [ReceiptPrinter.self])
public final class DefaultReceiptPrinter: ReceiptPrinter, Instantiable {
	public init() {}
}

@Instantiable(generateMock: .public)
public final class PaymentReceipt: Instantiable {
	public init(printer: (any ReceiptPrinter)?) {
		self.printer = printer
	}

	@Instantiated(onlyIfAvailable: true) private let printer: (any ReceiptPrinter)?
}
