import Feature
import SafeDI

struct Impl: Service { let tag: String }
/// Not Sendable.
final class Ctx { let name = "ctx" }

/// The generated caller: one fill per place, one dispatcher per enum. `A`'s plain enum is reached from `B`'s @Sendable
/// dispatcher, so its dispatcher, and every fill and dispatcher it reaches, are @Sendable.
func generatedA() -> A {
	let region = "eu"
	func __safeDI_a() -> A {
		@Sendable func __safeDI_serviceBuilder_A_service(_ scope: A.SafeDIScope_Service.service_Values) -> any Service { Impl(tag: "A:\(scope.marker.name):\(region)") }
		@Sendable func __safeDI_serviceBuilder_B_service(_ scope: B.SafeDIScope_Service.service_Values) -> any Service { Impl(tag: "B:\(scope.marker.name):\(region)") }
		@Sendable func __safeDI_serviceBuilder_C_service(_ scope: C.SafeDIScope_Service.service_Values) -> any Service { Impl(tag: "C:\(region)") }
		@Sendable func __safeDI_serviceBuilder_A(_ scope: A.SafeDIScope_Service) -> any Service {
			switch scope {
			case let .service(scope): __safeDI_serviceBuilder_A_service(scope)
			case let .bBuilder(scope): __safeDI_serviceBuilder_B(scope)
			case let .c(scope): __safeDI_serviceBuilder_C(scope)
			}
		}
		@Sendable func __safeDI_serviceSendableBuilder_A(_ scope: A.SafeDIScope_Service_Sendable) -> any Service {
			switch scope {
			case let .bBuilder_Sendable(scope): __safeDI_serviceSendableBuilder_B(scope)
			}
		}
		@Sendable func __safeDI_serviceBuilder_B(_ scope: B.SafeDIScope_Service) -> any Service {
			switch scope {
			case let .service(scope): __safeDI_serviceBuilder_B_service(scope)
			}
		}
		@Sendable func __safeDI_serviceSendableBuilder_B(_ scope: B.SafeDIScope_Service_Sendable) -> any Service {
			switch scope {
			case let .aBuilder(scope): __safeDI_serviceBuilder_A(scope)
			case let .aBuilder_Sendable(scope): __safeDI_serviceSendableBuilder_A(scope)
			}
		}
		@Sendable func __safeDI_serviceBuilder_C(_ scope: C.SafeDIScope_Service) -> any Service {
			switch scope {
			case let .service(scope): __safeDI_serviceBuilder_C_service(scope)
			}
		}
		return A(serviceBuilder: __safeDI_serviceBuilder_A, serviceSendableBuilder: __safeDI_serviceSendableBuilder_A)
	}
	return __safeDI_a()
}

/// A person's call: the plain closure captures a non-Sendable value, and reads how deep a place is.
func handWrittenA(ctx: Ctx) -> A {
	func openA(_ scope: A.SafeDIScope_Service, _ depth: Int) -> any Service {
		switch scope {
		case .service: Impl(tag: "A\(depth)")
		case .bBuilder(.service): Impl(tag: "B\(depth + 1)")
		case .c: Impl(tag: "C\(depth + 1)")
		}
	}
	@Sendable func openASendable(_ scope: A.SafeDIScope_Service_Sendable, _ depth: Int) -> any Service {
		switch scope {
		case let .bBuilder_Sendable(.aBuilder(scope)): Impl(tag: "deep " + openDeepA(scope, depth + 2).tag)
		case let .bBuilder_Sendable(.aBuilder_Sendable(scope)): openASendable(scope, depth + 2)
		}
	}
	@Sendable func openDeepA(_ scope: A.SafeDIScope_Service, _ depth: Int) -> any Service {
		switch scope {
		case .service: Impl(tag: "A\(depth)")
		case .bBuilder: Impl(tag: "B\(depth + 1)")
		case .c: Impl(tag: "C\(depth + 1)")
		}
	}
	return A(serviceBuilder: { scope in Impl(tag: openA(scope, 0).tag + ":" + ctx.name) }, serviceSendableBuilder: { openASendable($0, 0) })
}

func generatedS() -> S {
	func __safeDI_s() -> S {
		func __safeDI_serviceBuilder_S_service(_ scope: S.SafeDIScope_Service.service_Values) -> any Service { Impl(tag: "S") }
		func __safeDI_serviceBuilder_S(_ scope: S.SafeDIScope_Service) -> any Service {
			switch scope {
			case let .service(scope): __safeDI_serviceBuilder_S_service(scope)
			case let .nextBuilder(scope): __safeDI_serviceBuilder_S(scope)
			}
		}
		return S(serviceBuilder: __safeDI_serviceBuilder_S)
	}
	return __safeDI_s()
}

func walk(_ a: A) -> [String] {
	let b1 = a.bBuilder.instantiate()
	let a2 = b1.aBuilder.instantiate()
	let b3 = a2.bBuilder.instantiate()
	let a4 = b3.aBuilder.instantiate()
	return [a.service.tag, a.c.service.tag, b1.service.tag, a2.service.tag, a2.c.service.tag, b3.service.tag, a4.service.tag]
}

@main struct Main {
	static func main() {
		print(walk(generatedA()))
		print(walk(handWrittenA(ctx: Ctx())))
		let s = generatedS()
		print([s.service.tag, s.nextBuilder.instantiate().nextBuilder.instantiate().service.tag])
	}
}
