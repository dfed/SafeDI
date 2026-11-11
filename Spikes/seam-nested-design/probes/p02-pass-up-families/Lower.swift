// Module Lower: seam `Inner`, with a plain enum, a @Sendable enum (it calls seam `Job` inside a @Sendable function) and a
// staged place of its own; and seam `Job`.
import SafeDI

public protocol Service: Sendable { var tag: String { get } }
public final class Analytics: Sendable { public let name: String; public init(name: String) {
	self.name = name
} }

public final class Job: Instantiable {
	public let w: any Service
	init(w: any Service) {
		self.w = w
	}
}

extension Job {
	@frozen
	public enum SafeDIScope_Service {
		case w(w_Values)

		public struct w_Values {
			public let analytics: Analytics
		}
	}

	public convenience init(analytics: Analytics, serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		let __safeDI_serviceBuilder = serviceBuilder
		let w: any Service = __safeDI_serviceBuilder(.w(SafeDIScope_Service.w_Values(analytics: analytics)))
		self.init(w: w)
	}
}

public final class Panel: Instantiable {
	public let service: any Service
	init(service: any Service) {
		self.service = service
	}
}

public final class Inner: Instantiable {
	public let x: any Service
	public let jobBuilder: SendableInstantiator<Job>
	public let panelBuilder: SendableInstantiator<Panel>
	init(x: any Service, jobBuilder: SendableInstantiator<Job>, panelBuilder: SendableInstantiator<Panel>) {
		self.x = x; self.jobBuilder = jobBuilder; self.panelBuilder = panelBuilder
	}

	public func tags() -> [String] {
		[x.tag, jobBuilder.instantiate().w.tag, panelBuilder.instantiate().service.tag]
	}
}

extension Inner {
	@frozen
	public enum SafeDIScope_Service {
		case x(x_Values)

		public struct x_Values {
			public let analytics: Analytics
		}
	}

	@frozen
	public enum SafeDIScope_Service_Sendable {
		case jobBuilder(Job.SafeDIScope_Service)
	}

	public enum SafeDIScope_Service_panelBuilder_service {
		public struct Outer {
			public let analytics: Analytics
			public let x: any Service
		}

		public struct Inner {}
	}

	public convenience init(
		analytics: Analytics,
		serviceBuilder: @escaping (SafeDIScope_Service) -> any Service,
		serviceSendableBuilder: @escaping @Sendable (SafeDIScope_Service_Sendable) -> any Service,
		serviceBuilder_panelBuilder_service: @escaping (SafeDIScope_Service_panelBuilder_service.Outer) -> @Sendable (SafeDIScope_Service_panelBuilder_service.Inner) -> any Service,
	) {
		let __safeDI_serviceBuilder = serviceBuilder
		let __safeDI_serviceSendableBuilder = serviceSendableBuilder
		let __safeDI_serviceBuilder_panelBuilder_service = serviceBuilder_panelBuilder_service
		let x: any Service = __safeDI_serviceBuilder(.x(SafeDIScope_Service.x_Values(analytics: analytics)))
		@Sendable
		func __safeDI_jobBuilder() -> Job {
			Job(analytics: analytics, serviceBuilder: { __safeDI_serviceSendableBuilder(.jobBuilder($0)) })
		}
		let jobBuilder = SendableInstantiator<Job>(__safeDI_jobBuilder)
		let __safeDI_serviceBuilder_panelBuilder_service_Inner = __safeDI_serviceBuilder_panelBuilder_service(SafeDIScope_Service_panelBuilder_service.Outer(analytics: analytics, x: x))
		@Sendable
		func __safeDI_panelBuilder() -> Panel {
			let service: any Service = __safeDI_serviceBuilder_panelBuilder_service_Inner(SafeDIScope_Service_panelBuilder_service.Inner())
			return Panel(service: service)
		}
		let panelBuilder = SendableInstantiator<Panel>(__safeDI_panelBuilder)
		self.init(x: x, jobBuilder: jobBuilder, panelBuilder: panelBuilder)
	}
}
