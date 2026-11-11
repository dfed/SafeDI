import Feature
import SafeDI

struct Impl: Service { let tag: String }
final class Ctx { let name = "ctx" }

func make() -> Feature {
	let ctx = Ctx()
	@Sendable
	func __safeDI_serviceSendableBuilder_jobBuilder_w_service(_: Job.SafeDIScope_Service.w_service_Values) -> any Service {
		Impl(tag: ctx.name)
	}
	@Sendable
	func __safeDI_serviceSendableBuilder(_ scope: Feature.SafeDIScope_Service_Sendable) -> any Service {
		switch scope {
		case let .jobBuilder(scope):
			switch scope {
			case let .w_service(scope): __safeDI_serviceSendableBuilder_jobBuilder_w_service(scope)
			}
		}
	}
	return Feature(
		analytics: Analytics(name: "an"),
		serviceBuilder: { _ in Impl(tag: "plain") },
		serviceSendableBuilder: __safeDI_serviceSendableBuilder,
		serviceBuilder_panelBuilder_service: { _ in { _ in Impl(tag: "staged") } },
	)
}
