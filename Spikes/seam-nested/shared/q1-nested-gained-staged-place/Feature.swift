// Hand-written. The nested shape after `Inner` gained a place inside a @Sendable function. That place cannot be a case of
// any enum: it is staged, a closure type of its own, so `Outer` gains a required builder.
import SafeDI

public protocol Service { var tag: String { get } }

public final class Panel: Instantiable {
	public let service: any Service
	init(service: any Service) {
		self.service = service
	}
}

public final class Inner {
	public let x: any Service
	public let panelBuilder: SendableInstantiator<Panel>
	init(x: any Service, panelBuilder: SendableInstantiator<Panel>) {
		self.x = x
		self.panelBuilder = panelBuilder
	}
}

extension Inner {
	@frozen
	public enum SafeDIScope_Service {
		case x_service(x_service_Values)

		public struct x_service_Values {}
	}

	public enum SafeDIScope_Service_panelBuilder_service {
		public struct Outer {}
		public struct Inner {}
	}

	public convenience init(
		serviceBuilder __safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service,
		serviceBuilder_panelBuilder_service __safeDI_serviceBuilder_panelBuilder_service: @escaping (SafeDIScope_Service_panelBuilder_service.Outer) -> @Sendable (SafeDIScope_Service_panelBuilder_service.Inner) -> any Service,
	) {
		let x: any Service = __safeDI_serviceBuilder(.x_service(SafeDIScope_Service.x_service_Values()))
		let __safeDI_stage = __safeDI_serviceBuilder_panelBuilder_service(SafeDIScope_Service_panelBuilder_service.Outer())
		@Sendable
		func __safeDI_panelBuilder() -> Panel {
			Panel(service: __safeDI_stage(SafeDIScope_Service_panelBuilder_service.Inner()))
		}
		self.init(x: x, panelBuilder: SendableInstantiator<Panel>(__safeDI_panelBuilder))
	}
}

public final class Outer {
	public let own: any Service
	public let inner: Inner
	init(own: any Service, inner: Inner) {
		self.own = own
		self.inner = inner
	}
}

extension Outer {
	@frozen
	public enum SafeDIScope_Service {
		case own(own_Values)
		case inner(Inner.SafeDIScope_Service)

		public struct own_Values {}
	}

	public convenience init(
		serviceBuilder __safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service,
		serviceBuilder_inner_panelBuilder_service __safeDI_serviceBuilder_inner_panelBuilder_service: @escaping (Inner.SafeDIScope_Service_panelBuilder_service.Outer) -> @Sendable (Inner.SafeDIScope_Service_panelBuilder_service.Inner) -> any Service,
	) {
		func __safeDI_serviceBuilder_inner(_ scope: Inner.SafeDIScope_Service) -> any Service {
			__safeDI_serviceBuilder(.inner(scope))
		}
		self.init(own: __safeDI_serviceBuilder(.own(SafeDIScope_Service.own_Values())), inner: Inner(serviceBuilder: __safeDI_serviceBuilder_inner, serviceBuilder_panelBuilder_service: __safeDI_serviceBuilder_inner_panelBuilder_service))
	}
}
