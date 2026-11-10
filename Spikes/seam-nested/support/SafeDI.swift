// Stands in for the SafeDI runtime module. `Instantiator` and `SendableInstantiator` are copied from
// Sources/SafeDI/DelayedInstantiation at dacc6da3, so that the spike compiles with nothing but swiftc.

public protocol Instantiable: SendableMetatype {
	associatedtype ForwardedProperties = Void
}

public final class Instantiator<T: Instantiable> {
	public init(_ instantiator: @escaping (T.ForwardedProperties) -> T) {
		self.instantiator = instantiator
	}

	public init(_ instantiator: @escaping () -> T) where T.ForwardedProperties == Void {
		self.instantiator = { _ in instantiator() }
	}

	public func instantiate(_ forwardedProperties: T.ForwardedProperties) -> T {
		instantiator(forwardedProperties)
	}

	public func instantiate() -> T where T.ForwardedProperties == Void {
		instantiator(())
	}

	private let instantiator: (T.ForwardedProperties) -> T
}

public final class SendableInstantiator<T: Instantiable>: Sendable {
	public init(_ instantiator: @escaping @Sendable (T.ForwardedProperties) -> T) {
		self.instantiator = instantiator
	}

	public init(_ instantiator: @escaping @Sendable () -> T) where T.ForwardedProperties == Void {
		self.instantiator = { _ in instantiator() }
	}

	public func instantiate(_ forwardedProperties: T.ForwardedProperties) -> T {
		instantiator(forwardedProperties)
	}

	public func instantiate() -> T where T.ForwardedProperties == Void {
		instantiator(())
	}

	private let instantiator: @Sendable (T.ForwardedProperties) -> T
}
