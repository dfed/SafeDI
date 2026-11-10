// Hand-written. Stands in for the caller SafeDI would generate: one function per place, and a dispatcher per builder.
import Feature
import SafeDI

struct Impl: Service { let tag: String }

/// Not Sendable.
final class Ctx {
	let name = "ctx"
	init() {}
}

struct Root {
	let feature: Feature

	init() {
		let ctx = Ctx()
		let region = "eu"
		let analytics = Analytics(name: "an")
		func __safeDI_feature() -> Feature {
			func __safeDI_serviceBuilder_a_service(_ scope: Feature.SafeDIScope_Service.a_service_Values) -> any Service {
				Impl(tag: "a:\(ctx.name):\(scope.analytics.name)")
			}
			func __safeDI_serviceBuilder_Inner_x_service(_ scope: Inner.SafeDIScope_Service.x_service_Values) -> any Service {
				Impl(tag: "x:\(ctx.name):\(scope.analytics.name)")
			}
			func __safeDI_serviceBuilder_Inner_y_service(_ scope: Inner.SafeDIScope_Service.y_service_Values) -> any Service {
				Impl(tag: "y:\(ctx.name)")
			}
			func __safeDI_serviceBuilder(_ scope: Feature.SafeDIScope_Service) -> any Service {
				switch scope {
				case let .a_service(scope): __safeDI_serviceBuilder_a_service(scope)
				case let .Inner_x_service(scope): __safeDI_serviceBuilder_Inner_x_service(scope)
				case let .Inner_y_service(scope): __safeDI_serviceBuilder_Inner_y_service(scope)
				}
			}
			@Sendable func __safeDI_serviceSendableBuilder_Job_w_service(_ scope: Job.SafeDIScope_Service.w_service_Values) -> any Service {
				Impl(tag: "w:\(region):\(scope.analytics.name)")
			}
			@Sendable func __safeDI_serviceSendableBuilder(_ scope: Feature.SafeDIScope_Service_Sendable) -> any Service {
				switch scope {
				case let .Job_w_service(scope): __safeDI_serviceSendableBuilder_Job_w_service(scope)
				}
			}
			func __safeDI_serviceBuilder_panelBuilder_service(_ scope: Feature.SafeDIScope_Service_panelBuilder_service.Outer) -> @Sendable (Feature.SafeDIScope_Service_panelBuilder_service.Inner) -> any Service {
				let outerName = ctx.name + "+" + scope.analytics.name
				@Sendable func __safeDI_serviceBuilder_panelBuilder_service_Inner(_ scope: Feature.SafeDIScope_Service_panelBuilder_service.Inner) -> any Service {
					Impl(tag: "panel:\(outerName):\(region)")
				}
				return __safeDI_serviceBuilder_panelBuilder_service_Inner
			}
			return Feature(analytics: analytics, serviceBuilder: __safeDI_serviceBuilder, serviceSendableBuilder: __safeDI_serviceSendableBuilder, serviceBuilder_panelBuilder_service: __safeDI_serviceBuilder_panelBuilder_service)
		}
		feature = __safeDI_feature()
	}
}

@main struct Main {
	static func main() {
		print(Root().feature.tags())
	}
}
