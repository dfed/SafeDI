// Hand-written. Stands in for what SafeDI would generate under the NESTED shape for two seams that reach each other:
// SeamA builds SeamB lazily through an Instantiator, and SeamB builds SeamA. Each case holding another seam's enum is
// `indirect`, which needs no cycle analysis: the generator would mark every such case.
import SafeDI

public protocol Service { var tag: String { get } }

/// Not Sendable. A value of the seam that the place's payload carries.
public final class Marker {
	public let name: String
	init(name: String) {
		self.name = name
	}
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
	@frozen
	public enum SafeDIScope_Service {
		case service(service_Values)
		indirect case bBuilder(SeamB.SafeDIScope_Service)

		public struct service_Values {
			public let marker: Marker
		}
	}

	public convenience init(serviceBuilder __safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		let marker = Marker(name: "A")
		let service: any Service = __safeDI_serviceBuilder(.service(SafeDIScope_Service.service_Values(marker: marker)))
		func __safeDI_bBuilder() -> SeamB {
			func __safeDI_serviceBuilder_bBuilder(_ scope: SeamB.SafeDIScope_Service) -> any Service {
				__safeDI_serviceBuilder(.bBuilder(scope))
			}
			return SeamB(serviceBuilder: __safeDI_serviceBuilder_bBuilder)
		}
		let bBuilder = Instantiator<SeamB>(__safeDI_bBuilder)
		self.init(service: service, bBuilder: bBuilder)
	}
}

extension SeamB {
	@frozen
	public enum SafeDIScope_Service {
		case service(service_Values)
		indirect case a(SeamA.SafeDIScope_Service)

		public struct service_Values {
			public let marker: Marker
		}
	}

	public convenience init(serviceBuilder __safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		let marker = Marker(name: "B")
		let service: any Service = __safeDI_serviceBuilder(.service(SafeDIScope_Service.service_Values(marker: marker)))
		func __safeDI_serviceBuilder_a(_ scope: SeamA.SafeDIScope_Service) -> any Service {
			__safeDI_serviceBuilder(.a(scope))
		}
		let a = SeamA(serviceBuilder: __safeDI_serviceBuilder_a)
		self.init(service: service, a: a)
	}
}
