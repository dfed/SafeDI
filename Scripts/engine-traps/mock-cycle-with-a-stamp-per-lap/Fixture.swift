import SafeDI

// A lazily builds B and B lazily builds A, entered at A beneath two types with a token each and at the root. Every A
// instantiates a stamp of its own, and the leaves of that A and of the B it builds read that stamp and the token of
// the entry. So each lap must get a new stamp, each B the stamp of the A that built it, and each entry its own
// overrides.

@Instantiable(isRoot: true, generateMock: true)
public final class Root: Instantiable {
	public init(token: Token, left: Left, right: Right, aBuilder: Instantiator<A>) {
		self.token = token
		self.left = left
		self.right = right
		self.aBuilder = aBuilder
	}

	@Instantiated let token: Token
	@Instantiated let left: Left
	@Instantiated let right: Right
	@Instantiated let aBuilder: Instantiator<A>
}

@Instantiable
public final class Left: Instantiable {
	public init(token: Token, aBuilder: Instantiator<A>) {
		self.token = token
		self.aBuilder = aBuilder
	}

	@Instantiated let token: Token
	@Instantiated let aBuilder: Instantiator<A>
}

@Instantiable
public final class Right: Instantiable {
	public init(token: Token, aBuilder: Instantiator<A>) {
		self.token = token
		self.aBuilder = aBuilder
	}

	@Instantiated let token: Token
	@Instantiated let aBuilder: Instantiator<A>
}

@Instantiable
public final class A: Instantiable {
	public init(stamp: Stamp, leaf: Leaf, bBuilder: Instantiator<B>) {
		self.stamp = stamp
		self.leaf = leaf
		self.bBuilder = bBuilder
	}

	@Instantiated let stamp: Stamp
	@Instantiated let leaf: Leaf
	@Instantiated let bBuilder: Instantiator<B>
}

@Instantiable
public final class B: Instantiable {
	public init(leaf: Leaf, aBuilder: Instantiator<A>) {
		self.leaf = leaf
		self.aBuilder = aBuilder
	}

	@Instantiated let leaf: Leaf
	@Instantiated let aBuilder: Instantiator<A>
}

@Instantiable
public final class Leaf: Instantiable {
	public init(token: Token, stamp: Stamp, name: String = "built") {
		self.token = token
		self.stamp = stamp
		self.name = name
	}

	@Received let token: Token
	@Received let stamp: Stamp
	let name: String
}

@Instantiable
public final class Stamp: Instantiable {
	public init(name: String = "built") {
		self.name = name
	}

	public let name: String
}

@Instantiable
public final class Token: Instantiable {
	public init() {}
}
