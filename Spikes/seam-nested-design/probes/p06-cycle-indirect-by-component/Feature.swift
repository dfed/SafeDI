// Seams that reach each other, with `indirect` only on a case whose enum is in the same strongly connected component of the
// enum graph as the enum that holds it.
//
//   A: own `service`; `bBuilder: Instantiator<B>` (plain code); `c: C` (plain code)
//   B: own `service`; `aBuilder: SendableInstantiator<A>` (inside a @Sendable function)
//   C: own `service`
//   S: own `service`; `nextBuilder: Instantiator<S>` (re-enters itself)
//
// Enum graph:  A.plain -> B.plain, C.plain          B.plain -> (nothing)
//              A.Sendable -> B.Sendable             B.Sendable -> A.plain, A.Sendable
//              S.plain -> S.plain
// Components with a cycle: {A.Sendable, B.Sendable} and {S.plain}. Nothing else is recursive.
import SafeDI

public protocol Service: Sendable { var tag: String { get } }
public final class Marker: Sendable { public let name: String; init(name: String) { self.name = name } }

public final class C: Instantiable {
	public let service: any Service
	init(service: any Service) { self.service = service }
}

extension C {
	@frozen public enum SafeDIScope_Service {
		case service(service_Values)

		public struct service_Values {}
	}

	public convenience init(serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		self.init(service: serviceBuilder(.service(SafeDIScope_Service.service_Values())))
	}
}

public final class A: Instantiable {
	public let service: any Service
	public let bBuilder: Instantiator<B>
	public let c: C
	init(service: any Service, bBuilder: Instantiator<B>, c: C) { self.service = service; self.bBuilder = bBuilder; self.c = c }
}

public final class B: Instantiable {
	public let service: any Service
	public let aBuilder: SendableInstantiator<A>
	init(service: any Service, aBuilder: SendableInstantiator<A>) { self.service = service; self.aBuilder = aBuilder }
}

extension A {
	@frozen public enum SafeDIScope_Service {
		case service(service_Values)
		case bBuilder(B.SafeDIScope_Service)
		case c(C.SafeDIScope_Service)

		public struct service_Values {
			public let marker: Marker
		}
	}

	@frozen public enum SafeDIScope_Service_Sendable {
		indirect case bBuilder_Sendable(B.SafeDIScope_Service_Sendable)
	}

	public convenience init(
		serviceBuilder: @escaping (SafeDIScope_Service) -> any Service,
		serviceSendableBuilder: @escaping @Sendable (SafeDIScope_Service_Sendable) -> any Service,
	) {
		let __safeDI_serviceBuilder = serviceBuilder
		let __safeDI_serviceSendableBuilder = serviceSendableBuilder
		let marker = Marker(name: "A")
		let service: any Service = __safeDI_serviceBuilder(.service(SafeDIScope_Service.service_Values(marker: marker)))
		func __safeDI_bBuilder() -> B {
			B(serviceBuilder: { __safeDI_serviceBuilder(.bBuilder($0)) }, serviceSendableBuilder: { __safeDI_serviceSendableBuilder(.bBuilder_Sendable($0)) })
		}
		let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		let c = C(serviceBuilder: { __safeDI_serviceBuilder(.c($0)) })
		self.init(service: service, bBuilder: bBuilder, c: c)
	}
}

extension B {
	@frozen public enum SafeDIScope_Service {
		case service(service_Values)

		public struct service_Values {
			public let marker: Marker
		}
	}

	@frozen public enum SafeDIScope_Service_Sendable {
		case aBuilder(A.SafeDIScope_Service)
		indirect case aBuilder_Sendable(A.SafeDIScope_Service_Sendable)
	}

	public convenience init(
		serviceBuilder: @escaping (SafeDIScope_Service) -> any Service,
		serviceSendableBuilder: @escaping @Sendable (SafeDIScope_Service_Sendable) -> any Service,
	) {
		let __safeDI_serviceBuilder = serviceBuilder
		let __safeDI_serviceSendableBuilder = serviceSendableBuilder
		let marker = Marker(name: "B")
		let service: any Service = __safeDI_serviceBuilder(.service(SafeDIScope_Service.service_Values(marker: marker)))
		@Sendable func __safeDI_aBuilder() -> A {
			A(serviceBuilder: { __safeDI_serviceSendableBuilder(.aBuilder($0)) }, serviceSendableBuilder: { __safeDI_serviceSendableBuilder(.aBuilder_Sendable($0)) })
		}
		let aBuilder = SendableInstantiator<A>(__safeDI_aBuilder)
		self.init(service: service, aBuilder: aBuilder)
	}
}

public final class S: Instantiable {
	public let service: any Service
	public let nextBuilder: Instantiator<S>
	init(service: any Service, nextBuilder: Instantiator<S>) { self.service = service; self.nextBuilder = nextBuilder }
}

extension S {
	@frozen public enum SafeDIScope_Service {
		case service(service_Values)
		indirect case nextBuilder(SafeDIScope_Service)

		public struct service_Values {}
	}

	public convenience init(serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		let __safeDI_serviceBuilder = serviceBuilder
		let service: any Service = __safeDI_serviceBuilder(.service(SafeDIScope_Service.service_Values()))
		func __safeDI_nextBuilder() -> S {
			S(serviceBuilder: { __safeDI_serviceBuilder(.nextBuilder($0)) })
		}
		let nextBuilder = Instantiator<S>(__safeDI_nextBuilder)
		self.init(service: service, nextBuilder: nextBuilder)
	}
}
