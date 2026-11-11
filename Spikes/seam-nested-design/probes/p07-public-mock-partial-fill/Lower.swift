// Module Lower: public mocks of `Q` and of `P`, which calls `Q`'s once in plain code and once inside a @Sendable function.
import SafeDI

public protocol Service: Sendable { var tag: String { get } }
public final class Analytics: Sendable { public let name: String; public init(name: String) {
	self.name = name
} }

public final class Q: Instantiable {
	public let x: any Service
	public let y: any Service
	init(x: any Service, y: any Service) {
		self.x = x; self.y = y
	}
}

extension Q {
	@frozen
	public enum SafeDIMockScope_Service {
		case x(x_Values)
		case y(y_Values)

		public struct x_Values { public let analytics: Analytics }
		public struct y_Values {}
	}

	public static func mock(serviceBuilder: @escaping (SafeDIMockScope_Service) -> any Service) -> Q {
		let y: any Service = serviceBuilder(.y(SafeDIMockScope_Service.y_Values()))
		let analytics = Analytics(name: "q-an")
		let x: any Service = serviceBuilder(.x(SafeDIMockScope_Service.x_Values(analytics: analytics)))
		return Q(x: x, y: y)
	}
}

public final class P {
	public let a: any Service
	public let b: any Service
	public let q: Q
	public let qBuilder: SendableInstantiator<Q>
	init(a: any Service, b: any Service, q: Q, qBuilder: SendableInstantiator<Q>) {
		self.a = a; self.b = b; self.q = q; self.qBuilder = qBuilder
	}

	public func tags() -> [String] {
		let built = qBuilder.instantiate()
		return [a.tag, b.tag, q.x.tag, q.y.tag, built.x.tag, built.y.tag]
	}
}

extension P {
	@frozen
	public enum SafeDIMockScope_Service {
		case a(a_Values)
		case b(b_Values)
		case q(Q.SafeDIMockScope_Service)

		public struct a_Values { public let analytics: Analytics }
		public struct b_Values {}
	}

	@frozen
	public enum SafeDIMockScope_Service_Sendable {
		case qBuilder(Q.SafeDIMockScope_Service)
	}

	public static func mock(
		serviceBuilder: @escaping (SafeDIMockScope_Service) -> any Service,
		serviceSendableBuilder: @escaping @Sendable (SafeDIMockScope_Service_Sendable) -> any Service,
	) -> P {
		let b: any Service = serviceBuilder(.b(SafeDIMockScope_Service.b_Values()))
		let analytics = Analytics(name: "p-an")
		let a: any Service = serviceBuilder(.a(SafeDIMockScope_Service.a_Values(analytics: analytics)))
		let q = Q.mock(serviceBuilder: { serviceBuilder(.q($0)) })
		@Sendable
		func __safeDI_qBuilder() -> Q {
			Q.mock(serviceBuilder: { serviceSendableBuilder(.qBuilder($0)) })
		}
		let qBuilder = SendableInstantiator<Q>(__safeDI_qBuilder)
		return P(a: a, b: b, q: q, qBuilder: qBuilder)
	}
}
