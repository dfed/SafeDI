// Hand-written. Stands in for what SafeDI would generate under the NESTED shape for one inner seam that the outer seam
// calls twice: once in plain code (`mid`) and once inside a @Sendable function (`midBuilder`). `Mid` has a plain place of
// its own (`m_service`) and calls a further seam, `Deep`, inside a @Sendable function, so Mid has both families.
import SafeDI

public protocol Service { var tag: String { get } }

public final class Analytics {
	public let name: String
	public init(name: String) { self.name = name }
}

public final class Deep: Instantiable {
	public let service: any Service
	init(service: any Service) { self.service = service }
}

extension Deep {
	@frozen public enum SafeDIScope_Service {
		case d_service(d_service_Values)

		public struct d_service_Values {
			public let analytics: Analytics
		}
	}

	public convenience init(serviceBuilder __safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		self.init(service: __safeDI_serviceBuilder(.d_service(SafeDIScope_Service.d_service_Values(analytics: Analytics(name: "deep-analytics")))))
	}
}

public final class Mid: Instantiable {
	public let own: any Service
	public let deepBuilder: SendableInstantiator<Deep>

	init(own: any Service, deepBuilder: SendableInstantiator<Deep>) {
		self.own = own
		self.deepBuilder = deepBuilder
	}
}

extension Mid {
	@frozen public enum SafeDIScope_Service {
		case m_service(m_service_Values)

		public struct m_service_Values {
			public let analytics: Analytics
		}
	}

	@frozen public enum SafeDIScope_Service_Sendable {
		case deepBuilder(Deep.SafeDIScope_Service)
	}

	public convenience init(
		serviceBuilder __safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service,
		serviceSendableBuilder __safeDI_serviceSendableBuilder: @escaping @Sendable (SafeDIScope_Service_Sendable) -> any Service,
	) {
		let own: any Service = __safeDI_serviceBuilder(.m_service(SafeDIScope_Service.m_service_Values(analytics: Analytics(name: "mid-analytics"))))
		@Sendable func __safeDI_deepBuilder() -> Deep {
			func __safeDI_serviceBuilder_deepBuilder(_ scope: Deep.SafeDIScope_Service) -> any Service {
				__safeDI_serviceSendableBuilder(.deepBuilder(scope))
			}
			return Deep(serviceBuilder: __safeDI_serviceBuilder_deepBuilder)
		}
		self.init(own: own, deepBuilder: SendableInstantiator<Deep>(__safeDI_deepBuilder))
	}
}

public final class Top {
	public let own: any Service
	public let mid: Mid
	public let midBuilder: SendableInstantiator<Mid>

	init(own: any Service, mid: Mid, midBuilder: SendableInstantiator<Mid>) {
		self.own = own
		self.mid = mid
		self.midBuilder = midBuilder
	}

	public func tags() -> [String] {
		let built = midBuilder.instantiate()
		return [own.tag, mid.own.tag, mid.deepBuilder.instantiate().service.tag, built.own.tag, built.deepBuilder.instantiate().service.tag]
	}
}

extension Top {
	@frozen public enum SafeDIScope_Service {
		case own(own_Values)
		case mid(Mid.SafeDIScope_Service)

		public struct own_Values {}
	}

	/// An inner seam called inside a @Sendable function needs a case for each of the inner seam's enums.
	@frozen public enum SafeDIScope_Service_Sendable {
		case mid(Mid.SafeDIScope_Service_Sendable)
		case midBuilder(Mid.SafeDIScope_Service)
		case midBuilder_Sendable(Mid.SafeDIScope_Service_Sendable)
	}

	public convenience init(
		serviceBuilder __safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service,
		serviceSendableBuilder __safeDI_serviceSendableBuilder: @escaping @Sendable (SafeDIScope_Service_Sendable) -> any Service,
	) {
		let own: any Service = __safeDI_serviceBuilder(.own(SafeDIScope_Service.own_Values()))
		func __safeDI_serviceBuilder_mid(_ scope: Mid.SafeDIScope_Service) -> any Service {
			__safeDI_serviceBuilder(.mid(scope))
		}
		@Sendable func __safeDI_serviceSendableBuilder_mid(_ scope: Mid.SafeDIScope_Service_Sendable) -> any Service {
			__safeDI_serviceSendableBuilder(.mid(scope))
		}
		let mid = Mid(serviceBuilder: __safeDI_serviceBuilder_mid, serviceSendableBuilder: __safeDI_serviceSendableBuilder_mid)
		@Sendable func __safeDI_midBuilder() -> Mid {
			@Sendable func __safeDI_serviceBuilder_midBuilder(_ scope: Mid.SafeDIScope_Service) -> any Service {
				__safeDI_serviceSendableBuilder(.midBuilder(scope))
			}
			@Sendable func __safeDI_serviceSendableBuilder_midBuilder(_ scope: Mid.SafeDIScope_Service_Sendable) -> any Service {
				__safeDI_serviceSendableBuilder(.midBuilder_Sendable(scope))
			}
			return Mid(serviceBuilder: __safeDI_serviceBuilder_midBuilder, serviceSendableBuilder: __safeDI_serviceSendableBuilder_midBuilder)
		}
		self.init(own: own, mid: mid, midBuilder: SendableInstantiator<Mid>(__safeDI_midBuilder))
	}
}
