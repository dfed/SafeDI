import Feature
import SafeDI

struct Impl: Service { let tag: String }
final class Ctx { let name = "ctx" }

func make() -> Feature {
	let ctx = Ctx()
	return Feature(
		analytics: Analytics(name: "an"),
		serviceBuilder: { _ in Impl(tag: "plain") },
		serviceSendableBuilder: { _ in Impl(tag: ctx.name) },
		serviceBuilder_panelBuilder_service: { _ in { _ in Impl(tag: "staged") } },
	)
}
