// Hand-written, and NOT the proposal: nested with one @Sendable builder for every place, to show what separate builders avoid.
import SafeDI

public protocol Service { var tag: String { get } }

public final class Analytics {
	public let name: String
	public init(name: String) {
		self.name = name
	}
}

public final class Job: Instantiable {
	public let w: any Service
	init(w: any Service) {
		self.w = w
	}
}

extension Job {
	@frozen
	public enum SafeDIScope_Service {
		case w_service(w_service_Values)

		public struct w_service_Values {
			public let analytics: Analytics
		}
	}

	public convenience init(serviceBuilder __safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		let analytics = Analytics(name: "job-analytics")
		self.init(w: __safeDI_serviceBuilder(.w_service(SafeDIScope_Service.w_service_Values(analytics: analytics))))
	}
}

public final class Feature {
	public let a: any Service
	public let jobBuilder: SendableInstantiator<Job>

	init(a: any Service, jobBuilder: SendableInstantiator<Job>) {
		self.a = a
		self.jobBuilder = jobBuilder
	}
}

extension Feature {
	@frozen
	public enum SafeDIScope_Service {
		case a_service(a_service_Values)
		case jobBuilder(Job.SafeDIScope_Service)

		public struct a_service_Values {}
	}

	public convenience init(serviceBuilder __safeDI_serviceBuilder: @escaping @Sendable (SafeDIScope_Service) -> any Service) {
		let a: any Service = __safeDI_serviceBuilder(.a_service(SafeDIScope_Service.a_service_Values()))
		@Sendable
		func __safeDI_jobBuilder() -> Job {
			func __safeDI_serviceBuilder_jobBuilder(_ scope: Job.SafeDIScope_Service) -> any Service {
				__safeDI_serviceBuilder(.jobBuilder(scope))
			}
			return Job(serviceBuilder: __safeDI_serviceBuilder_jobBuilder)
		}
		self.init(a: a, jobBuilder: SendableInstantiator<Job>(__safeDI_jobBuilder))
	}
}
