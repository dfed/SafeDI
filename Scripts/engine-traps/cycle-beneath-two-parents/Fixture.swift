import SafeDI

// Two cycles, each built beneath two parents that hold a token and overrides of their own: A builds B lazily and B
// builds A lazily; and a node that forwards an id builds a reader of the id and, lazily, the next node.

@Instantiable(isRoot: true, generateMock: true)
public final class Root: Instantiable {
	public init(left: Left, right: Right) {
		self.left = left
		self.right = right
	}

	@Instantiated let left: Left
	@Instantiated let right: Right
}

@Instantiable
public final class Left: Instantiable {
	public init(token: Token, aBuilder: Instantiator<A>, nodeBuilder: Instantiator<Node>) {
		self.token = token
		self.aBuilder = aBuilder
		self.nodeBuilder = nodeBuilder
	}

	@Instantiated let token: Token
	@Instantiated let aBuilder: Instantiator<A>
	@Instantiated let nodeBuilder: Instantiator<Node>
}

@Instantiable
public final class Right: Instantiable {
	public init(token: Token, aBuilder: Instantiator<A>, nodeBuilder: Instantiator<Node>) {
		self.token = token
		self.aBuilder = aBuilder
		self.nodeBuilder = nodeBuilder
	}

	@Instantiated let token: Token
	@Instantiated let aBuilder: Instantiator<A>
	@Instantiated let nodeBuilder: Instantiator<Node>
}

@Instantiable
public final class A: Instantiable {
	public init(bBuilder: Instantiator<B>, leaf: Leaf) {
		self.bBuilder = bBuilder
		self.leaf = leaf
	}

	@Instantiated let bBuilder: Instantiator<B>
	@Instantiated let leaf: Leaf
}

@Instantiable
public final class B: Instantiable {
	public init(aBuilder: Instantiator<A>, leaf: Leaf) {
		self.aBuilder = aBuilder
		self.leaf = leaf
	}

	@Instantiated let aBuilder: Instantiator<A>
	@Instantiated let leaf: Leaf
}

@Instantiable
public final class Leaf: Instantiable {
	public init(token: Token, name: String = "built") {
		self.token = token
		self.name = name
	}

	@Received let token: Token
	let name: String
}

@Instantiable
public final class Node: Instantiable {
	public init(id: ID, reader: Reader, nodeBuilder: Instantiator<Node>) {
		self.id = id
		self.reader = reader
		self.nodeBuilder = nodeBuilder
	}

	@Forwarded let id: ID
	@Instantiated let reader: Reader
	@Instantiated let nodeBuilder: Instantiator<Node>
}

@Instantiable
public final class Reader: Instantiable {
	public init(id: ID, token: Token, name: String = "built") {
		self.id = id
		self.token = token
		self.name = name
	}

	@Received let id: ID
	@Received let token: Token
	let name: String
}

@Instantiable
public final class Token: Instantiable {
	public init() {}
}

@Instantiable
public final class ID: Instantiable {
	public init() {}
}
