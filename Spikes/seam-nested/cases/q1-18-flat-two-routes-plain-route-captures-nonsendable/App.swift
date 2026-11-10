import Feature
import SafeDI

struct Impl: Service { let tag: String }
final class Ctx { let name = "ctx" }

func make() -> Top {
	let ctx = Ctx()
	return Top(
		serviceBuilder: { _ in Impl(tag: "own:\(ctx.name)") },
		serviceSendableBuilder: { scope in
			switch scope {
			case .Mid_m_service: Impl(tag: "m:\(ctx.name)")
			case .Mid_Deep_d_service: Impl(tag: "d")
			}
		},
	)
}
