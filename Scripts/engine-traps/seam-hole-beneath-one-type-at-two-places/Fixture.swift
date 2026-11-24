import SafeDI

// A type whose module generates its own dependency tree and leaves one type, a service, for its caller to build. One
// type, a side, is built at two places: by value and by a builder. Each side
// instantiates a token of its own, an inner type that builds two pairs of the token and a service, and a node that
// forwards an id, builds a service and, lazily, the next node.

@Instantiable(generateDependencyTree: true)
public final class Feature: Instantiable {
	public init(leftSide: Side, rightSideBuilder: Instantiator<Side>) {
		self.leftSide = leftSide
		self.rightSideBuilder = rightSideBuilder
	}

	@Instantiated let leftSide: Side
	@Instantiated let rightSideBuilder: Instantiator<Side>
}

@Instantiable
public final class Side: Instantiable {
	public init(token: Token, inner: Inner, nodeBuilder: Instantiator<Node>) {
		self.token = token
		self.inner = inner
		self.nodeBuilder = nodeBuilder
	}

	@Instantiated let token: Token
	@Instantiated let inner: Inner
	@Instantiated let nodeBuilder: Instantiator<Node>
}

@Instantiable
public final class Inner: Instantiable {
	public init(pair: Pair, pairBuilder: Instantiator<Pair>) {
		self.pair = pair
		self.pairBuilder = pairBuilder
	}

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
public final class Node: Instantiable {
	public init(id: String, token: Token, service: Service, nodeBuilder: Instantiator<Node>) {
		self.id = id
		self.token = token
		self.service = service
		self.nodeBuilder = nodeBuilder
	}

	@Forwarded let id: String
	@Received let token: Token
	@Instantiated let service: Service
	@Instantiated let nodeBuilder: Instantiator<Node>
}

@Instantiable
public final class Token: Instantiable, Sendable {
	public init() {}
}

public final class Service: Sendable {
	public init(place: String) {
		self.place = place
	}

	public let place: String
}
