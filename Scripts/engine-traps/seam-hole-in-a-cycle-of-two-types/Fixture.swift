import SafeDI

// A type whose module generates its own dependency tree and leaves one type, a service, for its caller to build. One
// type, a side, is built at two places, each with a token of its own. Beneath a side, A lazily builds B and B lazily
// builds A, both under the label `next`, and each builds a service and a leaf that reads the token and builds a
// service.

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
	public init(token: Token, next: Instantiator<A>, leaf: Leaf) {
		self.token = token
		self.next = next
		self.leaf = leaf
	}

	@Instantiated let token: Token
	@Instantiated let next: Instantiator<A>
	@Instantiated let leaf: Leaf
}

@Instantiable
public final class A: Instantiable {
	public init(service: Service, leaf: Leaf, next: Instantiator<B>) {
		self.service = service
		self.leaf = leaf
		self.next = next
	}

	@Instantiated let service: Service
	@Instantiated let leaf: Leaf
	@Instantiated let next: Instantiator<B>
}

@Instantiable
public final class B: Instantiable {
	public init(service: Service, leaf: Leaf, next: Instantiator<A>) {
		self.service = service
		self.leaf = leaf
		self.next = next
	}

	@Instantiated let service: Service
	@Instantiated let leaf: Leaf
	@Instantiated let next: Instantiator<A>
}

@Instantiable
public final class Leaf: Instantiable {
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
