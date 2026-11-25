import SafeDI
import Synchronization

// Builders that cross isolation, with what makes a shared function easy to get wrong: a screen forwards an id,
// instantiates a stamp of its own and a clock nothing in the graph can build, and builds a header by value and by a
// builder that crosses isolation; the header reads the id, the stamp and the clock. The screen is built by two
// builders that cross isolation beneath two types and by one at the root.

@Instantiable(generateMock: true)
public final class Root: Instantiable, Sendable {
	public init(left: Left, right: Right, screenBuilder: SendableInstantiator<Screen>) {
		self.left = left
		self.right = right
		self.screenBuilder = screenBuilder
	}

	@Instantiated let left: Left
	@Instantiated let right: Right
	@Instantiated let screenBuilder: SendableInstantiator<Screen>
}

@Instantiable
public final class Left: Instantiable, Sendable {
	public init(screenBuilder: SendableInstantiator<Screen>) {
		self.screenBuilder = screenBuilder
	}

	@Instantiated let screenBuilder: SendableInstantiator<Screen>
}

@Instantiable
public final class Right: Instantiable, Sendable {
	public init(screenBuilder: SendableInstantiator<Screen>) {
		self.screenBuilder = screenBuilder
	}

	@Instantiated let screenBuilder: SendableInstantiator<Screen>
}

@Instantiable
public final class Screen: Instantiable, Sendable {
	public init(id: String, stamp: Stamp, clock: Clock, header: Header, headerBuilder: SendableInstantiator<Header>) {
		self.id = id
		self.stamp = stamp
		self.clock = clock
		self.header = header
		self.headerBuilder = headerBuilder
	}

	@Forwarded let id: String
	@Instantiated let stamp: Stamp
	@Instantiated let clock: Clock
	@Instantiated let header: Header
	@Instantiated let headerBuilder: SendableInstantiator<Header>
}

@Instantiable
public final class Header: Instantiable, Sendable {
	public init(id: String, stamp: Stamp, clock: Clock, name: String = "built") {
		self.id = id
		self.stamp = stamp
		self.clock = clock
		self.name = name
	}

	@Received let id: String
	@Received let stamp: Stamp
	@Received let clock: Clock
	let name: String
}

@Instantiable
public final class Stamp: Instantiable, Sendable {
	public init(name: String = "built") {
		self.name = name
	}

	public let name: String
}

public protocol Clock: AnyObject, Sendable {}

public final class SystemClock: Clock {
	public init() {}
}

// Counts how many times a name given as an override was asked for, so the probe can tell a name read once from a
// name read at each construction.
public enum Names {
	public static let asked = Mutex<[String: Int]>([:])

	public static func next(_ place: String) -> String {
		asked.withLock { asked in
			asked[place, default: 0] += 1
			return "\(place) \(asked[place, default: 0])"
		}
	}
}
