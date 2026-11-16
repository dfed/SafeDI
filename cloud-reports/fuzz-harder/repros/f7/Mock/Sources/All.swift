import SafeDI

public final class U: Sendable {}

@Instantiable(generateMock: true)
public final class M: Instantiable {
	public init(t0: LazilyInstantiated<U>, cBuilder: SendableInstantiator<C>) {
		self.t0 = t0
		self.cBuilder = cBuilder
	}

	@Instantiated let t0: LazilyInstantiated<U>
	@Instantiated let cBuilder: SendableInstantiator<C>
}

@Instantiable
public final class C: Instantiable, Sendable {
	public init(t0: U) {
		self.t0 = t0
	}

	@Received let t0: U
}
