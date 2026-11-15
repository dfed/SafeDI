import SafeDI

#SafeDIConfiguration(generatePlainDependencyTreeInitializers: true)

@MainActor
@Instantiable(generateDependencyTree: true)
public final class Inner: Instantiable {
	nonisolated public init(token: Token, leaf: Leaf) {
		self.token = token
		self.leaf = leaf
	}

	@Received let token: Token
	@Instantiated let leaf: Leaf
}

@Instantiable
public final class Leaf: Instantiable, Sendable {
	public init() {}
}

@Instantiable
public final class Token: Instantiable, Sendable {
	public init() {}
}

@Instantiable(isRoot: true)
public final class Root: Instantiable {
	public init(token: Token, inner: Inner) {
		self.token = token
		self.inner = inner
	}

	@Instantiated let token: Token
	@Instantiated let inner: Inner
}
