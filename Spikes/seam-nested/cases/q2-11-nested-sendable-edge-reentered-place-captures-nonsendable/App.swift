import Feature
import SafeDI

struct Impl: Service { let tag: String }
final class Ctx { let name = "ctx" }

func make() -> SeamA {
	let ctx = Ctx()
	return SeamA(
		serviceBuilder: { _ in Impl(tag: "top") },
		serviceSendableBuilder: { _ in Impl(tag: ctx.name) },
	)
}
