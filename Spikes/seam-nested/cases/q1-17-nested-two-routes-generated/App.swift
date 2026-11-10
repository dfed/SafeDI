// Hand-written. Stands in for the caller SafeDI would generate.
import Feature
import SafeDI

struct Impl: Service { let tag: String }
final class Ctx { let name = "ctx" }

struct Root {
	let top: Top

	init() {
		let ctx = Ctx()
		let region = "eu"
		func __safeDI_top() -> Top {
			func __safeDI_serviceBuilder_own(_ scope: Top.SafeDIScope_Service.own_Values) -> any Service {
				Impl(tag: "own:\(ctx.name)")
			}
			func __safeDI_serviceBuilder_mid_m_service(_ scope: Mid.SafeDIScope_Service.m_service_Values) -> any Service {
				Impl(tag: "m:\(ctx.name)")
			}
			func __safeDI_serviceBuilder(_ scope: Top.SafeDIScope_Service) -> any Service {
				switch scope {
				case let .own(scope): __safeDI_serviceBuilder_own(scope)
				case let .mid(scope):
					switch scope {
					case let .m_service(scope): __safeDI_serviceBuilder_mid_m_service(scope)
					}
				}
			}
			@Sendable func __safeDI_serviceSendableBuilder_mid_deepBuilder_d_service(_ scope: Deep.SafeDIScope_Service.d_service_Values) -> any Service {
				Impl(tag: "d-via-mid:\(region)")
			}
			@Sendable func __safeDI_serviceSendableBuilder_midBuilder_m_service(_ scope: Mid.SafeDIScope_Service.m_service_Values) -> any Service {
				Impl(tag: "m-via-builder:\(region)")
			}
			@Sendable func __safeDI_serviceSendableBuilder_midBuilder_deepBuilder_d_service(_ scope: Deep.SafeDIScope_Service.d_service_Values) -> any Service {
				Impl(tag: "d-via-builder:\(region)")
			}
			@Sendable func __safeDI_serviceSendableBuilder(_ scope: Top.SafeDIScope_Service_Sendable) -> any Service {
				switch scope {
				case let .mid(scope):
					switch scope {
					case let .deepBuilder(scope):
						switch scope {
						case let .d_service(scope): __safeDI_serviceSendableBuilder_mid_deepBuilder_d_service(scope)
						}
					}
				case let .midBuilder(scope):
					switch scope {
					case let .m_service(scope): __safeDI_serviceSendableBuilder_midBuilder_m_service(scope)
					}
				case let .midBuilder_Sendable(scope):
					switch scope {
					case let .deepBuilder(scope):
						switch scope {
						case let .d_service(scope): __safeDI_serviceSendableBuilder_midBuilder_deepBuilder_d_service(scope)
						}
					}
				}
			}
			return Top(serviceBuilder: __safeDI_serviceBuilder, serviceSendableBuilder: __safeDI_serviceSendableBuilder)
		}
		top = __safeDI_top()
	}
}

@main struct Main {
	static func main() {
		print(Root().top.tags())
	}
}
