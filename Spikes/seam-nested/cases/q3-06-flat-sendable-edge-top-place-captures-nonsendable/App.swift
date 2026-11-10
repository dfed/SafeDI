import Feature
import SafeDI

struct Impl: Service { let tag: String }
final class Ctx { let name = "ctx" }

func make() -> SeamA {
	let ctx = Ctx()
	return SeamA(serviceSendableBuilder: { scope in
		switch scope {
		case .service: Impl(tag: ctx.name)
		case .SeamB_service: Impl(tag: "B")
		}
	})
}
