// A call written before `Feature` reached `Inner` inside a @Sendable function: it has no `serviceSendableBuilder`.
import Feature
import Lower

struct Impl: Service { let tag: String }

func stale() -> Feature {
	Feature(analytics: Analytics(name: "an"), serviceBuilder: { _ in Impl(tag: "hand") }, serviceBuilder_Inner_panelBuilder_service: { _ in { _ in Impl(tag: "hand-p") } })
}
