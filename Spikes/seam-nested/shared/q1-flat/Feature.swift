// Hand-written. Stands in for what SafeDI would generate for the seam module under the FLAT builder shape.
//
// The same tree as shared/q1-nested: an inner seam's places are flat cases of the outer enum, carrying the inner payload.
import SafeDI

public protocol Service { var tag: String { get } }

/// Not Sendable, as real dependencies often are not.
public final class Analytics {
	public let name: String
	public init(name: String) { self.name = name }
}

public final class A {
	public let service: any Service
	init(service: any Service) { self.service = service }
}

public final class Panel: Instantiable {
	public let service: any Service
	init(service: any Service) { self.service = service }
}

public final class Inner {
	public let x: any Service
	public let y: any Service
	init(x: any Service, y: any Service) {
		self.x = x
		self.y = y
	}
}

extension Inner {
	@frozen public enum SafeDIScope_Service {
		case x_service(x_service_Values)
		case y_service(y_service_Values)

		public struct x_service_Values {
			public let analytics: Analytics
		}

		public struct y_service_Values {
			public let analytics: Analytics
			internal let x: any Service
		}
	}

	public convenience init(analytics: Analytics, serviceBuilder __safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		let x: any Service = __safeDI_serviceBuilder(.x_service(SafeDIScope_Service.x_service_Values(analytics: analytics)))
		let y: any Service = __safeDI_serviceBuilder(.y_service(SafeDIScope_Service.y_service_Values(analytics: analytics, x: x)))
		self.init(x: x, y: y)
	}
}

public final class Job: Instantiable {
	public let w: any Service
	init(w: any Service) { self.w = w }
}

extension Job {
	@frozen public enum SafeDIScope_Service {
		case w_service(w_service_Values)

		public struct w_service_Values {
			public let analytics: Analytics
		}
	}

	public convenience init(serviceBuilder __safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		let analytics = Analytics(name: "job-analytics")
		let w: any Service = __safeDI_serviceBuilder(.w_service(SafeDIScope_Service.w_service_Values(analytics: analytics)))
		self.init(w: w)
	}
}

public final class Feature {
	public let a: A
	public let inner: Inner
	public let jobBuilder: SendableInstantiator<Job>
	public let panelBuilder: SendableInstantiator<Panel>

	init(a: A, inner: Inner, jobBuilder: SendableInstantiator<Job>, panelBuilder: SendableInstantiator<Panel>) {
		self.a = a
		self.inner = inner
		self.jobBuilder = jobBuilder
		self.panelBuilder = panelBuilder
	}

	public func tags() -> [String] {
		[a.service.tag, inner.x.tag, inner.y.tag, jobBuilder.instantiate().w.tag, panelBuilder.instantiate().service.tag]
	}
}

extension Feature {
	@frozen public enum SafeDIScope_Service {
		case a_service(a_service_Values)
		case Inner_x_service(Inner.SafeDIScope_Service.x_service_Values)
		case Inner_y_service(Inner.SafeDIScope_Service.y_service_Values)

		public struct a_service_Values {
			public let analytics: Analytics
		}
	}

	@frozen public enum SafeDIScope_Service_Sendable {
		case Job_w_service(Job.SafeDIScope_Service.w_service_Values)
	}

	public enum SafeDIScope_Service_panelBuilder_service {
		public struct Outer {
			public let analytics: Analytics
		}

		public struct Inner {}
	}

	public convenience init(
		analytics: Analytics,
		serviceBuilder __safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service,
		serviceSendableBuilder __safeDI_serviceSendableBuilder: @escaping @Sendable (SafeDIScope_Service_Sendable) -> any Service,
		serviceBuilder_panelBuilder_service __safeDI_serviceBuilder_panelBuilder_service: @escaping (SafeDIScope_Service_panelBuilder_service.Outer) -> @Sendable (SafeDIScope_Service_panelBuilder_service.Inner) -> any Service,
	) {
		func __safeDI_a() -> A {
			let service: any Service = __safeDI_serviceBuilder(.a_service(SafeDIScope_Service.a_service_Values(analytics: analytics)))
			return A(service: service)
		}
		let a: A = __safeDI_a()
		func __safeDI_serviceBuilder_inner(_ scope: Inner.SafeDIScope_Service) -> any Service {
			switch scope {
			case let .x_service(scope): __safeDI_serviceBuilder(.Inner_x_service(scope))
			case let .y_service(scope): __safeDI_serviceBuilder(.Inner_y_service(scope))
			}
		}
		let inner = Inner(analytics: analytics, serviceBuilder: __safeDI_serviceBuilder_inner)
		@Sendable func __safeDI_jobBuilder() -> Job {
			func __safeDI_serviceBuilder_jobBuilder(_ scope: Job.SafeDIScope_Service) -> any Service {
				switch scope {
				case let .w_service(scope): __safeDI_serviceSendableBuilder(.Job_w_service(scope))
				}
			}
			return Job(serviceBuilder: __safeDI_serviceBuilder_jobBuilder)
		}
		let jobBuilder = SendableInstantiator<Job>(__safeDI_jobBuilder)
		let __safeDI_serviceBuilder_panelBuilder_service_Inner = __safeDI_serviceBuilder_panelBuilder_service(SafeDIScope_Service_panelBuilder_service.Outer(analytics: analytics))
		@Sendable func __safeDI_panelBuilder() -> Panel {
			let service: any Service = __safeDI_serviceBuilder_panelBuilder_service_Inner(SafeDIScope_Service_panelBuilder_service.Inner())
			return Panel(service: service)
		}
		let panelBuilder = SendableInstantiator<Panel>(__safeDI_panelBuilder)
		self.init(a: a, inner: inner, jobBuilder: jobBuilder, panelBuilder: panelBuilder)
	}
}
