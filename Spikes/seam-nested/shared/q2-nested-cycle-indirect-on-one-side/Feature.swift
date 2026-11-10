// Hand-written. The nested cycle with `indirect` on one of the two cases only, to show that one is enough for the compiler.
import SafeDI

public protocol Service { var tag: String { get } }

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
		indirect case bBuilder(SeamB.SafeDIScope_Service)

		public struct service_Values {}
	}

	public convenience init(serviceBuilder __safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		let service: any Service = __safeDI_serviceBuilder(.service(SafeDIScope_Service.service_Values()))
		func __safeDI_bBuilder() -> SeamB {
			func __safeDI_serviceBuilder_bBuilder(_ scope: SeamB.SafeDIScope_Service) -> any Service {
				__safeDI_serviceBuilder(.bBuilder(scope))
			}
			return SeamB(serviceBuilder: __safeDI_serviceBuilder_bBuilder)
		}
		self.init(service: service, bBuilder: Instantiator<SeamB>(__safeDI_bBuilder))
	}
}

extension SeamB {
	@frozen public enum SafeDIScope_Service {
		case service(service_Values)
		case a(SeamA.SafeDIScope_Service)

		public struct service_Values {}
	}

	public convenience init(serviceBuilder __safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		let service: any Service = __safeDI_serviceBuilder(.service(SafeDIScope_Service.service_Values()))
		func __safeDI_serviceBuilder_a(_ scope: SeamA.SafeDIScope_Service) -> any Service {
			__safeDI_serviceBuilder(.a(scope))
		}
		self.init(service: service, a: SeamA(serviceBuilder: __safeDI_serviceBuilder_a))
	}
}
