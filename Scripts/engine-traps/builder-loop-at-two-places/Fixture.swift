import SafeDI

// One loop of builders (A receives B's builder, B receives A's) built beneath two parents, each with a token of its
// own. Each parent's loop wraps its builder functions again by name inside the loop's functions.

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
	public init(token: Token, aBuilder: Instantiator<A>, bBuilder: Instantiator<B>) {
		self.token = token
		self.aBuilder = aBuilder
		self.bBuilder = bBuilder
	}

	@Instantiated let token: Token
	@Instantiated let aBuilder: Instantiator<A>
	@Instantiated let bBuilder: Instantiator<B>
}

@Instantiable
public final class Right: Instantiable {
	public init(token: Token, aBuilder: Instantiator<A>, bBuilder: Instantiator<B>) {
		self.token = token
		self.aBuilder = aBuilder
		self.bBuilder = bBuilder
	}

	@Instantiated let token: Token
	@Instantiated let aBuilder: Instantiator<A>
	@Instantiated let bBuilder: Instantiator<B>
}

@Instantiable
public final class A: Instantiable {
	public init(bBuilder: Instantiator<B>) {
		self.bBuilder = bBuilder
	}

	@Received let bBuilder: Instantiator<B>
	var note = ""
}

@Instantiable
public final class B: Instantiable {
	public init(aBuilder: Instantiator<A>, token: Token) {
		self.aBuilder = aBuilder
		self.token = token
	}

	@Received let aBuilder: Instantiator<A>
	@Received let token: Token
	var note = ""
}

@Instantiable
public final class Token: Instantiable {
	public init() {}
}
