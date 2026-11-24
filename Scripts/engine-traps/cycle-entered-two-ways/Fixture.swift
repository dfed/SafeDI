import SafeDI

// A cycle of two types the root enters at both: A builds B lazily and B builds A lazily. Beneath `aBuilder` the cycle
// closes on A's function, beneath `bBuilder` on B's, so each lap is handed the overrides of the entry it started from.

@Instantiable(isRoot: true, generateMock: true)
public final class Root: Instantiable {
	public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>) {
		self.aBuilder = aBuilder
		self.bBuilder = bBuilder
	}

	@Instantiated let aBuilder: Instantiator<A>
	@Instantiated let bBuilder: Instantiator<B>
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
	public init(name: String = "built") {
		self.name = name
	}

	let name: String
}
