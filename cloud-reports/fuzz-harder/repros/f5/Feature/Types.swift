import SafeDI

public protocol T0Protocol {}

extension T0: T0Protocol {}

public struct AnyT0: T0Protocol {
	public init(_ value: any T0Protocol) {
		self.value = value
	}

	public let value: any T0Protocol
}

@Instantiable
public final class Analytics: Instantiable {
	public init() {}
}

@Instantiable
public final class T3: Instantiable {
	public init() {}
}

@Instantiable(generateMock: .public, customMockName: "customMock")
public final class T0: Instantiable {
	init(t3: T3, analytics: LazilyInstantiated<Analytics>) {
		self.t3 = t3
		self.analytics = analytics
	}

	@Instantiated let t3: T3
	@Received let analytics: LazilyInstantiated<Analytics>

	public static func customMock(t3: T3, analytics: LazilyInstantiated<Analytics>) -> T0 {
		T0(t3: t3, analytics: analytics)
	}
}
