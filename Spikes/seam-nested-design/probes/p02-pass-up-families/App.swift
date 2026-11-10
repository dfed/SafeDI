import Feature
import Lower
import SafeDI

struct Impl: Service { let tag: String }
/// Not Sendable.
final class Ctx { let name = "ctx" }

/// A person's call that opens nothing.
func ignoring() -> Feature {
	Feature(analytics: Analytics(name: "an"), serviceBuilder: { _ in Impl(tag: "hand") }, serviceSendableBuilder: { _ in Impl(tag: "hand-s") }, serviceBuilder_Inner_panelBuilder_service: { _ in { _ in Impl(tag: "hand-p") } })
}

/// A person's call that opens one route and not the others; the plain closure captures a non-Sendable value.
func opening(ctx: Ctx) -> Feature {
	Feature(
		analytics: Analytics(name: "an"),
		serviceBuilder: { scope in
			switch scope {
			case let .a_service(values): Impl(tag: "a:\(ctx.name):\(values.analytics.name)")
			case .inner(.x): Impl(tag: "inner.x:\(ctx.name)")
			}
		},
		serviceSendableBuilder: { scope in
			switch scope {
			case .inner_Sendable: Impl(tag: "inner's job")
			case .innerBuilder: Impl(tag: "built inner's own")
			case .innerBuilder_Sendable(.jobBuilder(.w)): Impl(tag: "built inner's job")
			}
		},
		serviceBuilder_Inner_panelBuilder_service: { outer in
			let analytics = outer.analytics
			return { _ in Impl(tag: "panel:\(analytics.name)") }
		},
	)
}

/// The generated caller. One fill per place (seam and path), one dispatcher per enum. `Inner`'s plain enum is reached from
/// the plain dispatcher and from the @Sendable one, so its dispatcher and its fill are @Sendable; `Feature`'s own place is
/// reached from plain code only, so its fill stays plain and captures `ctx`.
struct Root {
	let feature: Feature

	init(ctx: Ctx) {
		let analytics = Analytics(name: "an")
		let region = "eu"
		func __safeDI_feature() -> Feature {
			func __safeDI_serviceBuilder_Feature_a_service(_ scope: Feature.SafeDIScope_Service.a_service_Values) -> any Service {
				Impl(tag: "fill a:\(ctx.name):\(scope.analytics.name)")
			}
			@Sendable func __safeDI_serviceBuilder_Inner_x(_ scope: Inner.SafeDIScope_Service.x_Values) -> any Service {
				Impl(tag: "fill x:\(region)")
			}
			@Sendable func __safeDI_serviceBuilder_Job_w(_ scope: Job.SafeDIScope_Service.w_Values) -> any Service {
				Impl(tag: "fill w:\(region):\(scope.analytics.name)")
			}
			func __safeDI_serviceBuilder_Feature(_ scope: Feature.SafeDIScope_Service) -> any Service {
				switch scope {
				case let .a_service(scope): __safeDI_serviceBuilder_Feature_a_service(scope)
				case let .inner(scope): __safeDI_serviceBuilder_Inner(scope)
				}
			}
			@Sendable func __safeDI_serviceSendableBuilder_Feature(_ scope: Feature.SafeDIScope_Service_Sendable) -> any Service {
				switch scope {
				case let .inner_Sendable(scope): __safeDI_serviceSendableBuilder_Inner(scope)
				case let .innerBuilder(scope): __safeDI_serviceBuilder_Inner(scope)
				case let .innerBuilder_Sendable(scope): __safeDI_serviceSendableBuilder_Inner(scope)
				}
			}
			@Sendable func __safeDI_serviceBuilder_Inner(_ scope: Inner.SafeDIScope_Service) -> any Service {
				switch scope {
				case let .x(scope): __safeDI_serviceBuilder_Inner_x(scope)
				}
			}
			@Sendable func __safeDI_serviceSendableBuilder_Inner(_ scope: Inner.SafeDIScope_Service_Sendable) -> any Service {
				switch scope {
				case let .jobBuilder(scope): __safeDI_serviceBuilder_Job(scope)
				}
			}
			@Sendable func __safeDI_serviceBuilder_Job(_ scope: Job.SafeDIScope_Service) -> any Service {
				switch scope {
				case let .w(scope): __safeDI_serviceBuilder_Job_w(scope)
				}
			}
			@Sendable func __safeDI_serviceBuilder_Inner_panelBuilder_service(_ scope: Inner.SafeDIScope_Service_panelBuilder_service.Outer) -> @Sendable (Inner.SafeDIScope_Service_panelBuilder_service.Inner) -> any Service {
				let analytics = scope.analytics
				@Sendable func __safeDI_serviceBuilder_Inner_panelBuilder_service_Inner(_ scope: Inner.SafeDIScope_Service_panelBuilder_service.Inner) -> any Service {
					Impl(tag: "fill panel:\(analytics.name)")
				}
				return __safeDI_serviceBuilder_Inner_panelBuilder_service_Inner
			}
			return Feature(analytics: analytics, serviceBuilder: __safeDI_serviceBuilder_Feature, serviceSendableBuilder: __safeDI_serviceSendableBuilder_Feature, serviceBuilder_Inner_panelBuilder_service: __safeDI_serviceBuilder_Inner_panelBuilder_service)
		}
		feature = __safeDI_feature()
	}
}

@main struct Main {
	static func main() {
		let ctx = Ctx()
		print(ignoring().tags())
		print(opening(ctx: ctx).tags())
		print(Root(ctx: ctx).feature.tags())
	}
}
