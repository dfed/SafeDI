import Feature
import SafeDI

struct Impl: Service { let tag: String }

func make() -> SeamA {
	SeamA(serviceBuilder: { scope in
		switch scope {
		case .service: Impl(tag: "A0")
		case .bBuilder(.service): Impl(tag: "B1")
		case .bBuilder(.a(.service)): Impl(tag: "A2")
		}
	})
}
