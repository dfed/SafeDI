import SafeDI

// One type built three times: twice by value under two labels and once through an instantiator, each with a leaf of
// its own to override, and each beneath a parent that declares a token of its own.

@Instantiable(isRoot: true, generateMock: true)
public final class Root: Instantiable {
	public init(first: Holder, second: Holder, token: Token, thirdBuilder: Instantiator<Mid>) {
		self.first = first
		self.second = second
		self.token = token
		self.thirdBuilder = thirdBuilder
	}

	@Instantiated let first: Holder
	@Instantiated let second: Holder
	@Instantiated let token: Token
	@Instantiated let thirdBuilder: Instantiator<Mid>
}

@Instantiable
public final class Holder: Instantiable {
	public init(token: Token, mid: Mid) {
		self.token = token
		self.mid = mid
	}

	@Instantiated let token: Token
	@Instantiated let mid: Mid
}

@Instantiable
public final class Mid: Instantiable {
	public init(leaf: Leaf, token: Token) {
		self.leaf = leaf
		self.token = token
	}

	@Instantiated let leaf: Leaf
	@Received let token: Token
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
