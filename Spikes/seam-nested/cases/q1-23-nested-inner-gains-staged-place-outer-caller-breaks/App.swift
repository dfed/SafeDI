import Feature
import SafeDI

struct Impl: Service { let tag: String }

func make() -> Outer {
	Outer(serviceBuilder: { _ in Impl(tag: "x") })
}
