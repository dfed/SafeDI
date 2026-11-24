import SafeDI

// One type built inside two `@Sendable` builders and once in plain code, each place with overrides of its own, and a
// value the mock cannot build that each construction creates afresh.

@Instantiable(generateMock: true)
public final class Root: Instantiable, Sendable {
	public init(firstBuilder: SendableInstantiator<Screen>, secondBuilder: SendableInstantiator<Screen>, plain: Screen) {
		self.firstBuilder = firstBuilder
		self.secondBuilder = secondBuilder
		self.plain = plain
	}

	@Instantiated let firstBuilder: SendableInstantiator<Screen>
	@Instantiated let secondBuilder: SendableInstantiator<Screen>
	@Instantiated let plain: Screen
}

@Instantiable
public final class Screen: Instantiable, Sendable {
	public init(header: Header, clock: Clock) {
		self.header = header
		self.clock = clock
	}

	@Instantiated let header: Header
	@Instantiated let clock: Clock
}

@Instantiable
public final class Header: Instantiable, Sendable {
	public init(clock: Clock, name: String = "built") {
		self.clock = clock
		self.name = name
	}

	@Received let clock: Clock
	let name: String
}

public protocol Clock: AnyObject, Sendable {}

public final class SystemClock: Clock {
	public init() {}
}
