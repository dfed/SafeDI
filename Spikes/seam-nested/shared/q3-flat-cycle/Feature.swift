// Hand-written. Stands in for what SafeDI would generate under the FLAT shape for the cycle of shared/q2-nested-cycle.
// A passed-up place is the inner seam's type, then the inner case: SeamB_service in SeamA's enum, SeamA_service in SeamB's.
// A re-entered seam's own place maps back onto the case of that place: SeamB handed SeamA's `.SeamB_service` passes `.service`.
import SafeDI

public protocol Service { var tag: String { get } }

public final class Marker {
	public let name: String
	init(name: String) { self.name = name }
}

public final class SeamA: Instantiable {
	public let service: any Service
	public let bBuilder: Instantiator<SeamB>

	init(service: any Service, bBuilder: Instantiator<SeamB>) {
		self.service = service
		self.bBuilder = bBuilder
	}

	public func walk(_ remaining: Int) -> [String] {
		remaining == 0 ? [service.tag] : [service.tag] + bBuilder.instantiate().walk(remaining - 1)
	}
}

public final class SeamB: Instantiable {
	public let service: any Service
	public let a: SeamA

	init(service: any Service, a: SeamA) {
		self.service = service
		self.a = a
	}

	public func walk(_ remaining: Int) -> [String] {
		remaining == 0 ? [service.tag] : [service.tag] + a.walk(remaining - 1)
	}
}

extension SeamA {
	@frozen public enum SafeDIScope_Service {
		case service(service_Values)
		case SeamB_service(SeamB.SafeDIScope_Service.service_Values)

		public struct service_Values {
			public let marker: Marker
		}
	}

	public convenience init(serviceBuilder __safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		let marker = Marker(name: "A")
		let service: any Service = __safeDI_serviceBuilder(.service(SafeDIScope_Service.service_Values(marker: marker)))
		func __safeDI_bBuilder() -> SeamB {
			func __safeDI_serviceBuilder_SeamB(_ scope: SeamB.SafeDIScope_Service) -> any Service {
				switch scope {
				case let .service(scope): __safeDI_serviceBuilder(.SeamB_service(scope))
				case let .SeamA_service(scope): __safeDI_serviceBuilder(.service(scope))
				}
			}
			return SeamB(serviceBuilder: __safeDI_serviceBuilder_SeamB)
		}
		let bBuilder = Instantiator<SeamB>(__safeDI_bBuilder)
		self.init(service: service, bBuilder: bBuilder)
	}
}

extension SeamB {
	@frozen public enum SafeDIScope_Service {
		case service(service_Values)
		case SeamA_service(SeamA.SafeDIScope_Service.service_Values)

		public struct service_Values {
			public let marker: Marker
		}
	}

	public convenience init(serviceBuilder __safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		let marker = Marker(name: "B")
		let service: any Service = __safeDI_serviceBuilder(.service(SafeDIScope_Service.service_Values(marker: marker)))
		func __safeDI_serviceBuilder_SeamA(_ scope: SeamA.SafeDIScope_Service) -> any Service {
			switch scope {
			case let .service(scope): __safeDI_serviceBuilder(.SeamA_service(scope))
			case let .SeamB_service(scope): __safeDI_serviceBuilder(.service(scope))
			}
		}
		let a = SeamA(serviceBuilder: __safeDI_serviceBuilder_SeamA)
		self.init(service: service, a: a)
	}
}
