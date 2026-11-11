// Module Feature: seam `Feature` (a struct) has a plain place of its own and reaches `Inner` by two routes: `inner`, in plain
// code, and `innerBuilder`, inside a @Sendable function. It fills nothing.
import Lower
import SafeDI

public final class A { public let service: any Service; init(service: any Service) {
	self.service = service
} }

public struct Feature {
	public let a: A
	public let inner: Inner
	public let innerBuilder: SendableInstantiator<Inner>
	init(a: A, inner: Inner, innerBuilder: SendableInstantiator<Inner>) {
		self.a = a; self.inner = inner; self.innerBuilder = innerBuilder
	}

	public func tags() -> [String] {
		[a.service.tag] + inner.tags() + innerBuilder.instantiate().tags()
	}
}

extension Feature {
	@frozen
	public enum SafeDIScope_Service {
		case a_service(a_service_Values)
		/// `Inner`'s plain enum, on the route in plain code.
		case inner(Inner.SafeDIScope_Service)

		public struct a_service_Values {
			public let analytics: Analytics
		}
	}

	@frozen
	public enum SafeDIScope_Service_Sendable {
		/// `Inner`'s @Sendable enum, on the route in plain code: the closure passed for it must be @Sendable.
		case inner_Sendable(Inner.SafeDIScope_Service_Sendable)
		/// `Inner`'s plain enum, on the route inside a @Sendable function.
		case innerBuilder(Inner.SafeDIScope_Service)
		/// `Inner`'s @Sendable enum, on that route.
		case innerBuilder_Sendable(Inner.SafeDIScope_Service_Sendable)
	}

	public init(
		analytics: Analytics,
		serviceBuilder: @escaping (SafeDIScope_Service) -> any Service,
		serviceSendableBuilder: @escaping @Sendable (SafeDIScope_Service_Sendable) -> any Service,
		// `Inner`'s staged place, passed up by its site, once for both routes. Its first stage is @Sendable, since the
		// route inside the @Sendable function captures it.
		serviceBuilder_Inner_panelBuilder_service: @escaping @Sendable (Inner.SafeDIScope_Service_panelBuilder_service.Outer) -> @Sendable (Inner.SafeDIScope_Service_panelBuilder_service.Inner) -> any Service,
	) {
		let __safeDI_serviceBuilder = serviceBuilder
		let __safeDI_serviceSendableBuilder = serviceSendableBuilder
		let __safeDI_serviceBuilder_Inner_panelBuilder_service = serviceBuilder_Inner_panelBuilder_service
		func __safeDI_a() -> A {
			let service: any Service = __safeDI_serviceBuilder(.a_service(SafeDIScope_Service.a_service_Values(analytics: analytics)))
			return A(service: service)
		}
		let a: A = __safeDI_a()
		let inner = Inner(
			analytics: analytics,
			serviceBuilder: { __safeDI_serviceBuilder(.inner($0)) },
			serviceSendableBuilder: { __safeDI_serviceSendableBuilder(.inner_Sendable($0)) },
			serviceBuilder_panelBuilder_service: __safeDI_serviceBuilder_Inner_panelBuilder_service,
		)
		@Sendable
		func __safeDI_innerBuilder() -> Inner {
			Inner(
				analytics: analytics,
				serviceBuilder: { __safeDI_serviceSendableBuilder(.innerBuilder($0)) },
				serviceSendableBuilder: { __safeDI_serviceSendableBuilder(.innerBuilder_Sendable($0)) },
				serviceBuilder_panelBuilder_service: __safeDI_serviceBuilder_Inner_panelBuilder_service,
			)
		}
		let innerBuilder = SendableInstantiator<Inner>(__safeDI_innerBuilder)
		self.init(a: a, inner: inner, innerBuilder: innerBuilder)
	}
}
