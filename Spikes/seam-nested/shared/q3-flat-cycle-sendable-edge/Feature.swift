// Hand-written. Stands in for what SafeDI would generate under the FLAT shape when the lazy edge of the cycle is a
// SendableInstantiator. SeamA passes its own place to a call inside a @Sendable function, so the place is in the
// @Sendable family alone, as its builder is @Sendable today.
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
	public enum SafeDIScope_Service_Sendable {
		case service(service_Values)
		case SeamB_service(SeamB.SafeDIScope_Service_Sendable.service_Values)

		public struct service_Values {
			public let marker: Marker
		}
	}

	public convenience init(serviceSendableBuilder __safeDI_serviceSendableBuilder: @escaping @Sendable (SafeDIScope_Service_Sendable) -> any Service) {
		let marker = Marker(name: "A")
		let service: any Service = __safeDI_serviceSendableBuilder(.service(SafeDIScope_Service_Sendable.service_Values(marker: marker)))
		@Sendable
		func __safeDI_bBuilder() -> SeamB {
			@Sendable
			func __safeDI_serviceSendableBuilder_SeamB(_ scope: SeamB.SafeDIScope_Service_Sendable) -> any Service {
				switch scope {
				case let .service(scope): __safeDI_serviceSendableBuilder(.SeamB_service(scope))
				case let .SeamA_service(scope): __safeDI_serviceSendableBuilder(.service(scope))
				}
			}
			return SeamB(serviceSendableBuilder: __safeDI_serviceSendableBuilder_SeamB)
		}
		let bBuilder = SendableInstantiator<SeamB>(__safeDI_bBuilder)
		self.init(service: service, bBuilder: bBuilder)
	}
}

extension SeamB {
	@frozen
	public enum SafeDIScope_Service_Sendable {
		case service(service_Values)
		case SeamA_service(SeamA.SafeDIScope_Service_Sendable.service_Values)

		public struct service_Values {
			public let marker: Marker
		}
	}

	public convenience init(serviceSendableBuilder __safeDI_serviceSendableBuilder: @escaping @Sendable (SafeDIScope_Service_Sendable) -> any Service) {
		let marker = Marker(name: "B")
		let service: any Service = __safeDI_serviceSendableBuilder(.service(SafeDIScope_Service_Sendable.service_Values(marker: marker)))
		@Sendable
		func __safeDI_serviceSendableBuilder_SeamA(_ scope: SeamA.SafeDIScope_Service_Sendable) -> any Service {
			switch scope {
			case let .service(scope): __safeDI_serviceSendableBuilder(.SeamA_service(scope))
			case let .SeamB_service(scope): __safeDI_serviceSendableBuilder(.service(scope))
			}
		}
		let a = SeamA(serviceSendableBuilder: __safeDI_serviceSendableBuilder_SeamA)
		self.init(service: service, a: a)
	}
}
