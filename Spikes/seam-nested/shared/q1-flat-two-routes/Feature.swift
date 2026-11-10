// Hand-written. Stands in for what SafeDI would generate under the FLAT shape for the tree of shared/q1-nested-two-routes.
// Each place is one case however many calls present it, and its sendability joins those of the routes, as a site's does
// today: Mid's m_service is presented by a plain call and a @Sendable one, so it is in the @Sendable family alone.
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
		case Deep_d_service(Deep.SafeDIScope_Service.d_service_Values)
	}

	public convenience init(
		serviceBuilder __safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service,
		serviceSendableBuilder __safeDI_serviceSendableBuilder: @escaping @Sendable (SafeDIScope_Service_Sendable) -> any Service,
	) {
		let own: any Service = __safeDI_serviceBuilder(.m_service(SafeDIScope_Service.m_service_Values(analytics: Analytics(name: "mid-analytics"))))
		@Sendable func __safeDI_deepBuilder() -> Deep {
			func __safeDI_serviceBuilder_deepBuilder(_ scope: Deep.SafeDIScope_Service) -> any Service {
				switch scope {
				case let .d_service(scope): __safeDI_serviceSendableBuilder(.Deep_d_service(scope))
				}
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

		public struct own_Values {}
	}

	@frozen public enum SafeDIScope_Service_Sendable {
		case Mid_m_service(Mid.SafeDIScope_Service.m_service_Values)
		case Mid_Deep_d_service(Deep.SafeDIScope_Service.d_service_Values)
	}

	public convenience init(
		serviceBuilder __safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service,
		serviceSendableBuilder __safeDI_serviceSendableBuilder: @escaping @Sendable (SafeDIScope_Service_Sendable) -> any Service,
	) {
		let own: any Service = __safeDI_serviceBuilder(.own(SafeDIScope_Service.own_Values()))
		@Sendable func __safeDI_serviceBuilder_Mid(_ scope: Mid.SafeDIScope_Service) -> any Service {
			switch scope {
			case let .m_service(scope): __safeDI_serviceSendableBuilder(.Mid_m_service(scope))
			}
		}
		@Sendable func __safeDI_serviceSendableBuilder_Mid(_ scope: Mid.SafeDIScope_Service_Sendable) -> any Service {
			switch scope {
			case let .Deep_d_service(scope): __safeDI_serviceSendableBuilder(.Mid_Deep_d_service(scope))
			}
		}
		let mid = Mid(serviceBuilder: __safeDI_serviceBuilder_Mid, serviceSendableBuilder: __safeDI_serviceSendableBuilder_Mid)
		@Sendable func __safeDI_midBuilder() -> Mid {
			Mid(serviceBuilder: __safeDI_serviceBuilder_Mid, serviceSendableBuilder: __safeDI_serviceSendableBuilder_Mid)
		}
		self.init(own: own, mid: mid, midBuilder: SendableInstantiator<Mid>(__safeDI_midBuilder))
	}
}
