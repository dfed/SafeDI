// Types the other modules share. No call of a generated declaration is written here.
import SafeDI

/// The authenticated user, forwarded into trees at runtime.
public final class User: Sendable {
	public init(name: String) {
		self.name = name
	}

	public let name: String
}

@Instantiable
public final class Session: Instantiable, Sendable {
	public init() {}
}

@Instantiable
public final class Analytics: Instantiable, Sendable {
	public init() {}
}

@Instantiable
public final class Database: Instantiable, Sendable {
	public init() {}
}

@Instantiable
public final class Logger: Instantiable, Sendable {
	public init() {}
}

/// A protocol with a default implementation, as "Making protocols `@Instantiable`" declares `UserService`.
public protocol StringStorage: AnyObject {
	func string(forKey key: String) -> String?
}

@Instantiable(fulfillingAdditionalTypes: [StringStorage.self])
public final class DefaultStringStorage: StringStorage, Instantiable {
	public init() {}

	public func string(forKey _: String) -> String? {
		nil
	}
}
