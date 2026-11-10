// Stands in for module Feature and the code SafeDI would generate for seam `Feature` under the nested shape.
import SafeDI

public protocol Service: Sendable { var tag: String { get } }
public final class Analytics: Sendable { public let name: String; public init(name: String) { self.name = name } }
/// Not Sendable.
public final class Config {
	public let name: String
	public init(name: String) { self.name = name; Config.created += 1 }
	nonisolated(unsafe) public static var created = 0
}

public final class A { public let service: any Service; init(service: any Service) { self.service = service } }

public final class Feature {
	public let a: A
	public let lazy: LazilyInstantiated<any Service>
	public let maker: ErasedInstantiator<String, any Service>
	public let job: SendableLazilyInstantiated<any Service>
	public let jobMaker: SendableErasedInstantiator<String, any Service>
	init(a: A, lazy: LazilyInstantiated<any Service>, maker: ErasedInstantiator<String, any Service>, job: SendableLazilyInstantiated<any Service>, jobMaker: SendableErasedInstantiator<String, any Service>) {
		self.a = a; self.lazy = lazy; self.maker = maker; self.job = job; self.jobMaker = jobMaker
	}
}

extension Feature {
	@frozen public enum SafeDIScope_Service {
		case a_service(a_service_Values)
		case lazy(lazy_Values)
		/// An instantiator place whose fulfilling type the module cannot see: the forwarded value is the case's second value.
		case maker(maker_Values, String)

		public struct a_service_Values {
			public let analytics: Analytics
			public var config: Config { __safeDI_config.instance }
			let __safeDI_config: LazilyInstantiated<Config>

			init(analytics: Analytics, config: LazilyInstantiated<Config>) {
				self.analytics = analytics
				__safeDI_config = config
			}
		}

		public struct lazy_Values {
			public let analytics: Analytics
			internal let a: A
		}

		public struct maker_Values {
			public let analytics: Analytics
			public let lazy: LazilyInstantiated<any Service>
		}
	}

	public enum SafeDIScope_Service_job {
		public struct Outer {
			public let analytics: Analytics
			public let lazy: LazilyInstantiated<any Service>
			public let maker: ErasedInstantiator<String, any Service>
		}

		public struct Inner {}
	}

	public enum SafeDIScope_Service_jobMaker {
		public struct Outer {
			public let analytics: Analytics
			public let lazy: LazilyInstantiated<any Service>
			public let maker: ErasedInstantiator<String, any Service>
			public let job: SendableLazilyInstantiated<any Service>
		}

		public struct Inner {}
	}

	/// For people.
	public convenience init(
		analytics: Analytics,
		config: Config,
		serviceBuilder: @escaping (SafeDIScope_Service) -> any Service,
		serviceBuilder_job: @escaping (SafeDIScope_Service_job.Outer) -> @Sendable (SafeDIScope_Service_job.Inner) -> any Service,
		serviceBuilder_jobMaker: @escaping (SafeDIScope_Service_jobMaker.Outer) -> @Sendable (SafeDIScope_Service_jobMaker.Inner, String) -> any Service,
	) {
		self.init(__safeDI_analytics: analytics, __safeDI_config: config, __safeDI_serviceBuilder: serviceBuilder, __safeDI_serviceBuilder_job: serviceBuilder_job, __safeDI_serviceBuilder_jobMaker: serviceBuilder_jobMaker)
	}

	/// For generated code only.
	public convenience init(
		__safeDI_analytics analytics: Analytics,
		__safeDI_config: @autoclosure @escaping () -> Config,
		__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service,
		__safeDI_serviceBuilder_job: @escaping (SafeDIScope_Service_job.Outer) -> @Sendable (SafeDIScope_Service_job.Inner) -> any Service,
		__safeDI_serviceBuilder_jobMaker: @escaping (SafeDIScope_Service_jobMaker.Outer) -> @Sendable (SafeDIScope_Service_jobMaker.Inner, String) -> any Service,
	) {
		let config = LazilyInstantiated<Config>(__safeDI_config)
		func __safeDI_a() -> A {
			let service: any Service = __safeDI_serviceBuilder(.a_service(SafeDIScope_Service.a_service_Values(analytics: analytics, config: config)))
			return A(service: service)
		}
		let a: A = __safeDI_a()
		func __safeDI_lazy() -> any Service {
			__safeDI_serviceBuilder(.lazy(SafeDIScope_Service.lazy_Values(analytics: analytics, a: a)))
		}
		let lazy = LazilyInstantiated<any Service>(__safeDI_lazy)
		func __safeDI_maker(__safeDI_forwarded: String) -> any Service {
			__safeDI_serviceBuilder(.maker(SafeDIScope_Service.maker_Values(analytics: analytics, lazy: lazy), __safeDI_forwarded))
		}
		let maker = ErasedInstantiator<String, any Service> {
			__safeDI_maker(__safeDI_forwarded: $0)
		}
		let __safeDI_serviceBuilder_job_Inner = __safeDI_serviceBuilder_job(SafeDIScope_Service_job.Outer(analytics: analytics, lazy: lazy, maker: maker))
		@Sendable func __safeDI_job() -> any Service {
			__safeDI_serviceBuilder_job_Inner(SafeDIScope_Service_job.Inner())
		}
		let job = SendableLazilyInstantiated<any Service>(__safeDI_job)
		let __safeDI_serviceBuilder_jobMaker_Inner = __safeDI_serviceBuilder_jobMaker(SafeDIScope_Service_jobMaker.Outer(analytics: analytics, lazy: lazy, maker: maker, job: job))
		@Sendable func __safeDI_jobMaker(__safeDI_forwarded: String) -> any Service {
			__safeDI_serviceBuilder_jobMaker_Inner(SafeDIScope_Service_jobMaker.Inner(), __safeDI_forwarded)
		}
		let jobMaker = SendableErasedInstantiator<String, any Service> {
			__safeDI_jobMaker(__safeDI_forwarded: $0)
		}
		self.init(a: a, lazy: lazy, maker: maker, job: job, jobMaker: jobMaker)
	}
}
