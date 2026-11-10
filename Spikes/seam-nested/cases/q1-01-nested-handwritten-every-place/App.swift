// Hand-written caller: what a person would write against the nested shape.
import Feature
import SafeDI

struct Impl: Service { let tag: String }

/// Not Sendable.
final class Ctx {
	let name = "ctx"
	init() {}
}

@main struct Main {
	static func main() {
		let ctx = Ctx()
		let region = "eu"
		let feature = Feature(
			analytics: Analytics(name: "an"),
			serviceBuilder: { scope in
				switch scope {
				case let .a_service(values): Impl(tag: "a:\(ctx.name):\(values.analytics.name)")
				case let .inner(.x_service(values)): Impl(tag: "x:\(ctx.name):\(values.analytics.name)")
				case .inner(.y_service): Impl(tag: "y:\(ctx.name)")
				}
			},
			serviceSendableBuilder: { scope in
				switch scope {
				case let .jobBuilder(.w_service(values)): Impl(tag: "w:\(region):\(values.analytics.name)")
				}
			},
			serviceBuilder_panelBuilder_service: { outer in
				let outerName = ctx.name + "+" + outer.analytics.name
				return { _ in Impl(tag: "panel:\(outerName):\(region)") }
			},
		)
		print(feature.tags())
	}
}
