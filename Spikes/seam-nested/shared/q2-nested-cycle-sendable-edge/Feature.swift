// Hand-written. Stands in for what SafeDI would generate under the NESTED shape when the lazy edge of the cycle is a
// SendableInstantiator. SeamA's own place stays in the plain family at the top; a place re-entered through the @Sendable
// function arrives through SeamA's @Sendable builder.
import SafeDI

public protocol Service { var tag: String { get } }

public final class Marker {
	public let name: String
	init(name: String) {
		self.name = name
	}
}

public final class SeamA: Instantiable {
	public let service: any Service
	public let bBuilder: SendableInstantiator<SeamB>

	init(service: any Service, bBuilder: SendableInstantiator<SeamB>) {
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

		public struct service_Values {
			public let marker: Marker
		}
	}

	@frozen
	public enum SafeDIScope_Service_Sendable {
		indirect case bBuilder(SeamB.SafeDIScope_Service)
		indirect case bBuilder_Sendable(SeamB.SafeDIScope_Service_Sendable)
	}

	public convenience init(
		serviceBuilder __safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service,
		serviceSendableBuilder __safeDI_serviceSendableBuilder: @escaping @Sendable (SafeDIScope_Service_Sendable) -> any Service,
	) {
		let marker = Marker(name: "A")
		let service: any Service = __safeDI_serviceBuilder(.service(SafeDIScope_Service.service_Values(marker: marker)))
		@Sendable
		func __safeDI_bBuilder() -> SeamB {
			@Sendable
			func __safeDI_serviceBuilder_bBuilder(_ scope: SeamB.SafeDIScope_Service) -> any Service {
				__safeDI_serviceSendableBuilder(.bBuilder(scope))
			}
			@Sendable
			func __safeDI_serviceSendableBuilder_bBuilder(_ scope: SeamB.SafeDIScope_Service_Sendable) -> any Service {
				__safeDI_serviceSendableBuilder(.bBuilder_Sendable(scope))
			}
			return SeamB(serviceBuilder: __safeDI_serviceBuilder_bBuilder, serviceSendableBuilder: __safeDI_serviceSendableBuilder_bBuilder)
		}
		let bBuilder = SendableInstantiator<SeamB>(__safeDI_bBuilder)
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

	@frozen
	public enum SafeDIScope_Service_Sendable {
		indirect case a(SeamA.SafeDIScope_Service_Sendable)
	}

	public convenience init(
		serviceBuilder __safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service,
		serviceSendableBuilder __safeDI_serviceSendableBuilder: @escaping @Sendable (SafeDIScope_Service_Sendable) -> any Service,
	) {
		let marker = Marker(name: "B")
		let service: any Service = __safeDI_serviceBuilder(.service(SafeDIScope_Service.service_Values(marker: marker)))
		func __safeDI_serviceBuilder_a(_ scope: SeamA.SafeDIScope_Service) -> any Service {
			__safeDI_serviceBuilder(.a(scope))
		}
		@Sendable
		func __safeDI_serviceSendableBuilder_a(_ scope: SeamA.SafeDIScope_Service_Sendable) -> any Service {
			__safeDI_serviceSendableBuilder(.a(scope))
		}
		let a = SeamA(serviceBuilder: __safeDI_serviceBuilder_a, serviceSendableBuilder: __safeDI_serviceSendableBuilder_a)
		self.init(service: service, a: a)
	}
}
