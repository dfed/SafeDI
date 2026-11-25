import SafeDI

// The plainest mock sharing can meet: two types that each instantiate a token and, by value and by a builder, one
// holder of the token whose name an override can set. No cycle, no forwarded value, nothing that crosses isolation.

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
	public init(token: Token, holder: Holder, holderBuilder: Instantiator<Holder>) {
		self.token = token
		self.holder = holder
		self.holderBuilder = holderBuilder
	}

	@Instantiated let token: Token
	@Instantiated let holder: Holder
	@Instantiated let holderBuilder: Instantiator<Holder>
}

@Instantiable
public final class Right: Instantiable {
	public init(token: Token, holder: Holder, holderBuilder: Instantiator<Holder>) {
		self.token = token
		self.holder = holder
		self.holderBuilder = holderBuilder
	}

	@Instantiated let token: Token
	@Instantiated let holder: Holder
	@Instantiated let holderBuilder: Instantiator<Holder>
}

@Instantiable
public final class Holder: Instantiable {
	public init(token: Token, leaf: Leaf, name: String = "built") {
		self.token = token
		self.leaf = leaf
		self.name = name
	}

	@Received let token: Token
	@Instantiated let leaf: Leaf
	let name: String
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
public final class Token: Instantiable {
	public init() {}
}
