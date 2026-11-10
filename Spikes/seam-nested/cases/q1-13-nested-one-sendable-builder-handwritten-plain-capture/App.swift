import Feature
import SafeDI

struct Impl: Service { let tag: String }
final class Ctx { let name = "ctx" }

func make() -> Feature {
	let ctx = Ctx()
	return Feature(serviceBuilder: { scope in
		switch scope {
		case .a_service: Impl(tag: ctx.name)
		case .jobBuilder: Impl(tag: "job")
		}
	})
}
