import SafeDI

// A type whose module generates its own dependency tree and leaves one type, a service, for its caller to build. The
// service is built at five places: by a builder at the top, and by value and by a builder beneath two types that each
// instantiate a token of their own. A holder beside each service reads the token the service's place can read.

@Instantiable(generateDependencyTree: true)
public final class Feature: Instantiable {
	public init(left: Left, rightBuilder: Instantiator<Right>, pairBuilder: Instantiator<Pair>) {
		self.left = left
		self.rightBuilder = rightBuilder
		self.pairBuilder = pairBuilder
	}

	@Instantiated let left: Left
	@Instantiated let rightBuilder: Instantiator<Right>
	@Instantiated let pairBuilder: Instantiator<Pair>
}

@Instantiable
public final class Left: Instantiable {
	public init(token: Token, pair: Pair, pairBuilder: Instantiator<Pair>) {
		self.token = token
		self.pair = pair
		self.pairBuilder = pairBuilder
	}

	@Instantiated let token: Token
	@Instantiated let pair: Pair
	@Instantiated let pairBuilder: Instantiator<Pair>
}

@Instantiable
public final class Right: Instantiable {
	public init(token: Token, pair: Pair, pairBuilder: Instantiator<Pair>) {
		self.token = token
		self.pair = pair
		self.pairBuilder = pairBuilder
	}

	@Instantiated let token: Token
	@Instantiated let pair: Pair
	@Instantiated let pairBuilder: Instantiator<Pair>
}

@Instantiable
public final class Pair: Instantiable {
	public init(token: Token, service: Service) {
		self.token = token
		self.service = service
	}

	@Received let token: Token
	@Instantiated let service: Service
}

@Instantiable
public final class Token: Instantiable {
	public init() {}
}

public final class Service {
	public init(place: String) {
		self.place = place
	}

	public let place: String
}
