import Feature
import SafeDI

struct Impl: Service { let tag: String }
final class Ctx { let name = "ctx" }

func make() -> Feature {
	let ctx = Ctx()
	func __safeDI_serviceBuilder_a_service(_: Feature.SafeDIScope_Service.a_service_Values) -> any Service {
		Impl(tag: ctx.name)
	}
	@Sendable
	func __safeDI_serviceBuilder_jobBuilder_w_service(_: Job.SafeDIScope_Service.w_service_Values) -> any Service {
		Impl(tag: "job")
	}
	@Sendable
	func __safeDI_serviceBuilder(_ scope: Feature.SafeDIScope_Service) -> any Service {
		switch scope {
		case let .a_service(scope): __safeDI_serviceBuilder_a_service(scope)
		case let .jobBuilder(scope):
			switch scope {
			case let .w_service(scope): __safeDI_serviceBuilder_jobBuilder_w_service(scope)
			}
		}
	}
	return Feature(serviceBuilder: __safeDI_serviceBuilder)
}
