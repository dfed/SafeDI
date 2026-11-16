import SafeDI

@Instantiable
public final class T1: Instantiable, @unchecked Sendable {
	public init() {}
}

@Instantiable(isRoot: true, generateMock: true)
public final class Root: Instantiable {
	public init(t2Builder: SendableInstantiator<T2>) {
		self.t2Builder = t2Builder
	}

	@Instantiated let t2Builder: SendableInstantiator<T2>
}

@Instantiable
public final class T2: Instantiable, @unchecked Sendable {
	public init(t1Builder: Instantiator<T1>?) {
		self.t1Builder = t1Builder
	}

	@Received(onlyIfAvailable: true) let t1Builder: Instantiator<T1>?
}
