// Hand-written. Stands in for a generated caller that merges the fills of each builder into one function.
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
			func __safeDI_serviceBuilder(_ scope: Feature.SafeDIScope_Service) -> any Service {
				switch scope {
				case let .a_service(scope):
					Impl(tag: "a:\(ctx.name):\(scope.analytics.name)")
				case let .inner(scope):
					switch scope {
					case let .x_service(scope): Impl(tag: "x:\(ctx.name):\(scope.analytics.name)")
					case .y_service: Impl(tag: "y:\(ctx.name)")
					}
				}
			}
			@Sendable func __safeDI_serviceSendableBuilder(_ scope: Feature.SafeDIScope_Service_Sendable) -> any Service {
				switch scope {
				case let .jobBuilder(scope):
					switch scope {
					case let .w_service(scope): Impl(tag: "w:\(region):\(scope.analytics.name)")
					}
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
