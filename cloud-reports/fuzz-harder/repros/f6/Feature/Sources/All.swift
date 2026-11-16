import SafeDI

@Instantiable(isRoot: true)
public final class Root: Instantiable {
	public init(t2Builder: Instantiator<T2>, t4Builder: Instantiator<T4>, t3: T3) {
		self.t2Builder = t2Builder
		self.t4Builder = t4Builder
		self.t3 = t3
	}

	@Instantiated let t2Builder: Instantiator<T2>
	@Instantiated let t4Builder: Instantiator<T4>
	@Instantiated let t3: T3
}

@Instantiable
public final class T2: Instantiable {
	public init(t3: T3?) {
		self.t3 = t3
	}

	@Received(onlyIfAvailable: true) let t3: T3?
}

@Instantiable
public final class T3: Instantiable {
	public init(t4: T4) {
		self.t4 = t4
	}

	@Instantiated let t4: T4
}

@Instantiable
public final class T4: Instantiable {
	public init(t4BuilderAlias: Instantiator<T4>, t2Builder: Instantiator<T2>?) {
		self.t4BuilderAlias = t4BuilderAlias
		self.t2Builder = t2Builder
	}

	@Received(fulfilledByDependencyNamed: "t4Builder", ofType: Instantiator<T4>.self) let t4BuilderAlias: Instantiator<T4>
	@Received(onlyIfAvailable: true) let t2Builder: Instantiator<T2>?
}
