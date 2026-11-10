import Feature
import SafeDI

struct Impl: Service { let tag: String }

func make() -> Outer {
	Outer(serviceBuilder: { scope in
		switch scope {
		case .own: Impl(tag: "own")
		case .inner: Impl(tag: "inner")
		}
	})
}
