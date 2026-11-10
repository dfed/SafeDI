// Module Feature: the public mock of `M`, whose tree calls `P`'s public mock. This module can build `DefaultService`, which
// reads `analytics`: it fills each place whose values hold `analytics` (`P.a`, `Q.x`) and passes the others up (`P.b`, `Q.y`).
import Lower
import SafeDI

struct DefaultService: Service {
	let analytics: Analytics
	var tag: String { "filled:\(analytics.name)" }
}

public final class M {
	public let p: P
	init(p: P) { self.p = p }
}

extension M {
	@frozen public enum SafeDIMockScope_Service {
		case p(P.SafeDIMockScope_Service)
	}

	@frozen public enum SafeDIMockScope_Service_Sendable {
		case p_Sendable(P.SafeDIMockScope_Service_Sendable)
	}

	public static func mock(
		serviceBuilder: @escaping (SafeDIMockScope_Service) -> any Service,
		serviceSendableBuilder: @escaping @Sendable (SafeDIMockScope_Service_Sendable) -> any Service,
	) -> M {
		let __safeDI_serviceBuilder = serviceBuilder
		let __safeDI_serviceSendableBuilder = serviceSendableBuilder
		func __safeDI_p() -> P {
			func __safeDI_serviceBuilder_P_a(_ scope: P.SafeDIMockScope_Service.a_Values) -> any Service {
				let analytics = scope.analytics
				return DefaultService(analytics: analytics)
			}
			@Sendable func __safeDI_serviceBuilder_Q_x(_ scope: Q.SafeDIMockScope_Service.x_Values) -> any Service {
				let analytics = scope.analytics
				return DefaultService(analytics: analytics)
			}
			// Each dispatcher sends a place this module fills to its fill, and every other one to `passUp`, which hands this
			// mock's own builder the whole scope the call was given, under the case of the route.
			func __safeDI_serviceBuilder_P(_ scope: P.SafeDIMockScope_Service, passUp: () -> any Service) -> any Service {
				switch scope {
				case let .a(scope): __safeDI_serviceBuilder_P_a(scope)
				case .b: passUp()
				case let .q(scope): __safeDI_serviceBuilder_Q(scope, passUp: passUp)
				}
			}
			@Sendable func __safeDI_serviceSendableBuilder_P(_ scope: P.SafeDIMockScope_Service_Sendable, passUp: () -> any Service) -> any Service {
				switch scope {
				case let .qBuilder(scope): __safeDI_serviceBuilder_Q(scope, passUp: passUp)
				}
			}
			@Sendable func __safeDI_serviceBuilder_Q(_ scope: Q.SafeDIMockScope_Service, passUp: () -> any Service) -> any Service {
				switch scope {
				case let .x(scope): __safeDI_serviceBuilder_Q_x(scope)
				case .y: passUp()
				}
			}
			return P.mock(
				serviceBuilder: { scope in __safeDI_serviceBuilder_P(scope, passUp: { __safeDI_serviceBuilder(.p(scope)) }) },
				serviceSendableBuilder: { scope in __safeDI_serviceSendableBuilder_P(scope, passUp: { __safeDI_serviceSendableBuilder(.p_Sendable(scope)) }) },
			)
		}
		let p: P = __safeDI_p()
		return M(p: p)
	}
}
