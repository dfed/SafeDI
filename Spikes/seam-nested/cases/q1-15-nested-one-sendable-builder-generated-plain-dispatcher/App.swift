import Feature
import SafeDI

struct Impl: Service { let tag: String }
final class Ctx { let name = "ctx" }

func make() -> Feature {
	let ctx = Ctx()
	func __safeDI_serviceBuilder_a_service(_: Feature.SafeDIScope_Service.a_service_Values) -> any Service {
		Impl(tag: ctx.name)
	}
	func __safeDI_serviceBuilder(_ scope: Feature.SafeDIScope_Service) -> any Service {
		switch scope {
		case let .a_service(scope): __safeDI_serviceBuilder_a_service(scope)
		case .jobBuilder: Impl(tag: "job")
		}
	}
	return Feature(serviceBuilder: __safeDI_serviceBuilder)
}
